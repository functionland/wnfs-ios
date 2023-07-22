//
//  File.swift
//  
//
//  Created by Homayoun on 1/18/23.
//
import Foundation
import WnfsBindings
import CommonCrypto

public typealias Cid = String
private class WrapClosure<G, P> {
    fileprivate let get_closure: G
    fileprivate let put_closure: P
    init(get_closure: G, put_closure: P) {
        self.get_closure = get_closure
        self.put_closure = put_closure
    }
}

func sha256(data : Data) -> Data {
    var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return Data(hash)
}

func toData(ptr: UnsafePointer<UInt8>?, size: Int) -> Data? {
    // This will clone input c bytes to a swift Data class.
    let buffer = UnsafeBufferPointer(start: ptr, count: size)
    return Data(buffer: buffer)
}

public class WnfsResult<T>{
    private var _ok: Bool
    private var _error: String?
    private var _result: T
    public init(ok: Bool, error: String?, result: T) {
        self._ok = ok
        self._error = error
        self._result = result
    }
    
    public func ok() -> Bool {
        return self._ok
    }
    
    public func error() -> String?{
        return self._error
    }
    
    public func getResult()  -> T {
        return self._result
    }
}

enum MyError: Error {
    case runtimeError(String)
}
public class Wnfs {
    var blockStoreInterface: BlockStoreInterface
    public init(putFn: @escaping ((_ cid: Data, _ data: Data) throws -> Void), getFn: @escaping ((_ cid: Data) throws -> Data)) {
        // step 1
        let wrappedClosure = WrapClosure(get_closure: getFn, put_closure: putFn)
        let userdata = Unmanaged.passRetained(wrappedClosure).toOpaque()
        
        // step 2
        let cPutFn: @convention(c) (UnsafeMutableRawPointer?, RustBytes, RustBytes) -> RustResult_RustVoid = { (_ userdata: UnsafeMutableRawPointer?, _ cid: RustBytes, _ bytes: RustBytes) -> RustResult_RustVoid in
            let wrappedClosure: WrapClosure< (_ cid: Data) throws -> Data , (_ cid: Data, _ data: Data) throws -> Void> = Unmanaged.fromOpaque(userdata!).takeUnretainedValue()
            let _bts = toData(ptr: bytes.data, size: bytes.len)
            let _cid = toData(ptr: cid.data, size: cid.len)
            var err: UnsafeMutablePointer<CChar>!
            var ok: Bool = false
            if let cid = _cid , let bts = _bts {
                do {
                    try wrappedClosure.put_closure(cid, bts)
                    ok = true
                } catch let error {
                    err = strdup(error.localizedDescription)
                }
            }else{
                err = strdup("put data: cid and/or data is empty")
            }
            
            let swiftData = RustResult_RustVoid(ok: ok, err: RustString(str: err), result: RustVoid())
            let swiftDataPtr = UnsafeMutablePointer<RustResult_RustVoid>.allocate(capacity: 1)
            swiftDataPtr.initialize(to: swiftData)
            return swiftData
        }
        
        // step 3
        let cGetFn: @convention(c) (UnsafeMutableRawPointer?, RustBytes) -> RustResult_RustBytes = { (_ userdata: UnsafeMutableRawPointer?, _ cid: RustBytes) -> RustResult_RustBytes in
            let wrappedClosure: WrapClosure< (_ cid: Data) throws -> Data , (_ cid: Data, _ data: Data) throws -> Data> = Unmanaged.fromOpaque(userdata!).takeUnretainedValue()
            let _cid = toData(ptr: cid.data, size: cid.len)
            var err: UnsafeMutablePointer<CChar>!
            var ok: Bool = false
            var _result: Data? = nil
            if let cid = _cid {
                do {
                    _result = try wrappedClosure.get_closure(cid)
                    ok = true
                } catch let error {
                    err = strdup(error.localizedDescription)
                }
            }else{
                err = strdup("get data: cid argument is empty")
            }
            
            let result_ptr: UnsafePointer<UInt8>? = nil
            var result_count: Int = 0
            if let result = _result {
                let result_ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: result.count)
                result_count = result.count
                result.copyBytes(to: result_ptr, count: result.count)
                ok = true
            }else {
                err = strdup("get data: empty result")
            }
            let swiftData = RustResult_RustBytes(ok: ok, err: RustString(str: err), result: RustBytes(data: result_ptr, len: result_count, cap: result_count))
            let swiftDataPtr = UnsafeMutablePointer<RustResult_RustBytes>.allocate(capacity: 1)
            swiftDataPtr.initialize(to: swiftData)
            return swiftData
        }
        
        let cPutDeallocFn: @convention(c) (RustResult_RustVoid) -> Void = { (_ data: RustResult_RustVoid) in
            if data.err.str != nil{
                data.err.str.deallocate()
            }
        }
        
        let cGetDeallocFn: @convention(c) (RustResult_RustBytes) -> Void = { (_ data: RustResult_RustBytes) in
            if data.err.str != nil{
                data.err.str.deallocate()
            }
            if data.result.data != nil{
                data.result.data.deallocate()
            }
        }

        self.blockStoreInterface = BlockStoreInterface(userdata: userdata, put_fn: cPutFn, get_fn: cGetFn, dealloc_after_get: cGetDeallocFn, dealloc_after_put: cPutDeallocFn)
    }
    
    public func Init(wnfsKey: String) throws -> Cid {
        let msg = wnfsKey.data(using: .utf8)!
        let hashed = sha256(data: msg)
        var wnfs_key_ptr: UnsafePointer<UInt8>?
        var wnfs_key_size: Int?
        hashed.withUnsafeBytes { (unsafeBytes) in
            wnfs_key_ptr = unsafeBytes.bindMemory(to: UInt8.self).baseAddress!
            wnfs_key_size = unsafeBytes.count
        }
        let ptr = init_native(self.blockStoreInterface, RustBytes(data: wnfs_key_ptr, len: wnfs_key_size!, cap: wnfs_key_size!))
        return try self.consumeRustResult_RustString(ptr)
    }
    
    public  func LoadWithWNFSKey(wnfsKey: String, cid: Cid) throws  {
        let msg = wnfsKey.data(using: .utf8)!
        let hashed = sha256(data: msg)
        var wnfs_key_ptr: UnsafePointer<UInt8>?
        var wnfs_key_size: Int?
        hashed.withUnsafeBytes { (unsafeBytes) in
            wnfs_key_ptr = unsafeBytes.bindMemory(to: UInt8.self).baseAddress!
            wnfs_key_size = unsafeBytes.count
        }
        let cCid = makeRustString(from: cid)
        let ptr = load_with_wnfs_key_native(self.blockStoreInterface, RustBytes(data: wnfs_key_ptr, len: wnfs_key_size!, cap: wnfs_key_size!), cCid)
        
        return try self.consumeRustResult_RustVoid(ptr)
    }
    
    public func WriteFile(cid: Cid, remotePath: String, data: Data)  throws -> Cid {
        let content_arr_ptr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        let content_arr_size: Int? = data.count
        data.copyBytes(to: content_arr_ptr, count: data.count)
        let cCid = makeRustString(from: cid)
        
        let cRemotePath = makeRustString(from: remotePath)
        let ptr = write_file_native(self.blockStoreInterface, cCid,  cRemotePath, RustBytes(data: content_arr_ptr, len: content_arr_size!, cap: content_arr_size!))
        content_arr_ptr.deallocate()
        return try self.consumeRustResult_RustString(ptr)
    }
    
    public func WriteFileFromPath(cid: Cid, remotePath: String, fileUrl: URL) throws -> Cid  {
        let cCid = makeRustString(from: cid)
        
        let cRemotePath = makeRustString(from: remotePath)
        let cFilePath = makeRustString(from: fileUrl.path)
        let ptr = write_file_from_path_native(self.blockStoreInterface, cCid,  cRemotePath, cFilePath)
        
        
        
        
        
        
        return try self.consumeRustResult_RustString(ptr)
    }
    
    public func ReadFile(cid: Cid, remotePath: String) throws -> Data? {
        let cCid = makeRustString(from: cid)
        
        let cRemotePath = makeRustString(from: remotePath)
        let ptr = read_file_native(self.blockStoreInterface, cCid,  cRemotePath)
        
        let data = try consumeRustResult_RustBytes(ptr)
        
        
        return data
    }
    
    public func ReadFileToPath(cid: Cid, remotePath: String, fileUrl: URL) throws -> String? {
        let cCid = makeRustString(from: cid)
        
        let cRemotePath = makeRustString(from: remotePath)
        let cFilePath = makeRustString(from: fileUrl.path)
        
        
        let ptr = read_file_to_path_native(self.blockStoreInterface, cCid,  cRemotePath, cFilePath)
        let fileName = try consumeRustResult_RustString(ptr)
        
        
        
        
        return fileName
    }
    
    public func ReadFileStreamToPath(cid: Cid, remotePath: String, fileUrl: URL) throws -> String? {
        let cCid = makeRustString(from: cid)
        
        let cRemotePath = makeRustString(from: remotePath)
        let cFilePath = makeRustString(from: fileUrl.path)
        
        
        let ptr = read_filestream_to_path_native(self.blockStoreInterface, cCid,  cRemotePath, cFilePath)
        let fileName = try consumeRustResult_RustString(ptr)
        
        
        
        
        
        return fileName
    }
    
    public func MkDir(cid: Cid, remotePath: String) throws -> Cid{
        let cCid = makeRustString(from: cid)
        
        let cRemotePath = makeRustString(from: remotePath)
        let ptr = mkdir_native(self.blockStoreInterface, cCid,  cRemotePath)
        
        
        
        
        
        return try self.consumeRustResult_RustString(ptr)
    }
    
    public func Rm(cid: Cid, remotePath: String) throws -> Cid {
        let cCid = makeRustString(from: cid)
        
        let cRemotePath = makeRustString(from: remotePath)
        let ptr = rm_native(self.blockStoreInterface, cCid,  cRemotePath)
        
        
        
        
        
        return try self.consumeRustResult_RustString(ptr)
    }
    
    public func Cp(cid: Cid, remotePathFrom: String, remotePathTo: String) throws -> Cid {
        let cCid = makeRustString(from: cid)
        
        let cRemotePathFrom = makeRustString(from: remotePathFrom)
        let cRemotePathTo = makeRustString(from: remotePathTo)
        let ptr = cp_native(self.blockStoreInterface, cCid,  cRemotePathFrom, cRemotePathTo)
        
        
        
        
        
        
        return try self.consumeRustResult_RustString(ptr)
    }
    
    public func Ls(cid: Cid, remotePath: String) throws -> Data? {
        let cCid = makeRustString(from: cid)
        
        let cRemotePath = makeRustString(from: remotePath)
        let ptr = ls_native(self.blockStoreInterface, cCid,  cRemotePath)
        
        let data = try self.consumeRustResult_RustBytes(ptr)
        
        
        return data
    }
    
    public func Mv(cid: Cid, remotePathFrom: String, remotePathTo: String) throws -> Cid{
        let cCid = makeRustString(from: cid)
        
        let cRemotePathFrom = makeRustString(from: remotePathFrom)
        let cRemotePathTo = makeRustString(from: remotePathTo)
        let ptr = mv_native(self.blockStoreInterface, cCid,  cRemotePathFrom, cRemotePathTo)
        
        
        
        
        
        
        return try self.consumeRustResult_RustString(ptr)
    }
    
    
    private func consumeRustResult_RustBytes(_ r: RustResult_RustBytes) throws -> Data {
        if !r.ok {
            throw MyError.runtimeError(String(cString:  r.err.str))
        }

        if r.result.data == nil {
            throw MyError.runtimeError("nil RustResult bytes ptr")
        }
        let result = toData(ptr: r.result.data, size: r.result.len)
        rust_result_bytes_free(r)
        return result!
    }
    
    private func consumeRustResult_RustVoid(_ r: RustResult_RustVoid) throws -> Void {
        if !r.ok {
            throw MyError.runtimeError(String(cString:  r.err.str))
        }
    }
    
    private func consumeRustResult_RustString(_ r: RustResult_RustString) throws -> String {
        if !r.ok {
            throw MyError.runtimeError(String(cString:  r.err.str))
        }

        if r.result.str == nil {
            throw MyError.runtimeError("nil RustResult string ptr")
        }
        let result = String(cString: r.result.str)
        rust_result_string_free(r)
        return result
    }
    
    private func makeRustString(from str: String) -> RustString {
        return RustString(str: (str as NSString).utf8String)
    }
    
    private func freeRustString(rustString:  RustString){
        if rustString.str != nil {
            rustString.str.deallocate()
        }
    }
}
