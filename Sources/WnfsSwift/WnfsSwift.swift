//
//  File.swift
//  
//
//  Created by Homayoun on 1/18/23.
//
import Foundation
import WnfsBindings
import CryptoKit

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

func toData(ptr: UnsafePointer<UInt8>?, size: UnsafePointer<Int>?) -> Data? {
    // This will clone input c bytes to a swift Data class.
    guard let count = size else {
        return nil
    }
    let buffer = UnsafeBufferPointer(start: ptr, count: count.pointee)
    return Data(buffer: buffer)
}

public class WnfsConfig{
    private var cid: String
    private var privateRef: String
    public init(cid: String, privateRef: String) {
        self.cid = cid
        self.privateRef = privateRef
    }
    
    public func getCid()  -> String {
        return self.cid
    }
    
    public func getPrivateRef() -> String{
        return self.privateRef
    }
    
    public func Update(newConfig: WnfsConfig){
        self.cid = newConfig.cid
        self.privateRef = newConfig.privateRef
    }
}

enum MyError: Error {
    case runtimeError(String)
}
public class WnfsWrapper {
    var blockStoreInterface: BlockStoreInterface
    public init(putFn: @escaping ((_ data: Data?, _ codec: Int64) -> Data?), getFn: @escaping ((_ cid: Data?) -> Data?)) {
        // step 1
        let wrappedClosure = WrapClosure(get_closure: getFn, put_closure: putFn)
        let userdata = Unmanaged.passRetained(wrappedClosure).toOpaque()
        
        // step 2
        let cPutFn: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, UnsafePointer<Int>?, Int64) -> UnsafePointer<SwiftData>? = { (_ userdata: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ bytes_size: UnsafePointer<Int>?, _ codec: Int64) -> UnsafePointer<SwiftData>? in
            let wrappedClosure: WrapClosure< (_ cid: Data?) -> Data? , (_ data: Data?, _ codec: Int64) -> Data?> = Unmanaged.fromOpaque(userdata!).takeUnretainedValue()
            let bts = toData(ptr: bytes, size: bytes_size)
            guard let cid = wrappedClosure.put_closure(bts, codec) else{
                return nil
            }
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: cid.count)
            cid.copyBytes(to: ptr, count: cid.count)
            let swiftData = SwiftData(ptr: UnsafePointer<UInt8>(ptr), count: cid.count)
            let _result = UnsafeMutablePointer<SwiftData>.allocate(capacity: 1)
            _result.initialize(to: swiftData)
            let result: UnsafePointer<SwiftData>? = UnsafePointer(_result)
            return result
        }
        
        // step 3
        let cGetFn: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, UnsafePointer<Int>?) -> UnsafePointer<SwiftData>? = { (_ userdata: UnsafeMutableRawPointer?, _ cid: UnsafePointer<UInt8>?, _ cid_size: UnsafePointer<Int>?) -> UnsafePointer<SwiftData>? in
            let wrappedClosure: WrapClosure< (_ cid: Data?) -> Data? , (_ data: Data?, _ codec: Int64) -> Data?> = Unmanaged.fromOpaque(userdata!).takeUnretainedValue()
            let bts = toData(ptr: cid, size: cid_size)
            guard let data = wrappedClosure.get_closure(bts) else{
                return nil
            }

            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            data.copyBytes(to: ptr, count: data.count)
            let swiftData = SwiftData(ptr: UnsafePointer<UInt8>(ptr), count: data.count)
            let _result = UnsafeMutablePointer<SwiftData>.allocate(capacity: 1)
            _result.initialize(to: swiftData)
            let result: UnsafePointer<SwiftData>? = UnsafePointer(_result)
            return result
        }
        
        let cDeallocFn: @convention(c) (UnsafePointer<SwiftData>?) -> Void = { (_ data: UnsafePointer<SwiftData>?) in
            data?.deallocate()
        }

        self.blockStoreInterface = BlockStoreInterface(userdata: userdata, put_fn: cPutFn, get_fn: cGetFn, dealloc: cDeallocFn)
    }
    
    public func CreatePrivateForest(wnfsKey: String) throws -> WnfsConfig {
        let result = create_private_forest_native(self.blockStoreInterface)
        guard let ccid = result else {
            throw MyError.runtimeError("Empty cid response")
        }
        let cid = String(cString: ccid)
        // Freeing the memory
        cstring_free(ccid)
        
        return try self.createRootDir(cid: cid, wnfsKey: wnfsKey)
    }
    
    private func createRootDir(cid: String, wnfsKey: String) throws -> WnfsConfig {
        let msg = wnfsKey.data(using: .utf8)!
        let hashed = sha256(data: msg)
        var wnfs_key_ptr: UnsafePointer<UInt8>?
        var wnfs_key_size: Int?
        hashed.withUnsafeBytes { (unsafeBytes) in
            wnfs_key_ptr = unsafeBytes.bindMemory(to: UInt8.self).baseAddress!
            wnfs_key_size = unsafeBytes.count
        }
        let ptr = create_root_dir_native(self.blockStoreInterface, wnfs_key_size!, wnfs_key_ptr!, makeCString(from: cid))
        
        guard let config = self.unwrapConfigPtr(ptr: ptr) else{
            throw MyError.runtimeError("null config ptr")
        }
        return config
    }
    
    public func WriteFile(wnfsConfig: WnfsConfig, remotePath: String, data: Data)  throws -> WnfsConfig {
        let content_arr_ptr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        let content_arr_size: Int? = data.count
        data.copyBytes(to: content_arr_ptr, count: data.count)
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePath = makeCString(from: remotePath)
        let ptr = write_file_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePath, content_arr_size!, content_arr_ptr)
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePath)
        content_arr_ptr.deallocate()
        
        guard let config = self.unwrapConfigPtr(ptr: ptr) else{
            throw MyError.runtimeError("null config ptr")
        }
        return config
    }
    
    public func WriteFileFromPath(wnfsConfig: WnfsConfig, remotePath: String, fileUrl: URL) throws -> WnfsConfig  {
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePath = makeCString(from: remotePath)
        let cFilePath = makeCString(from: fileUrl.path)
        let ptr = write_file_from_path_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePath, cFilePath)
        
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePath)
        freeCString(cString: cFilePath)
        
        guard let config = self.unwrapConfigPtr(ptr: ptr) else{
            throw MyError.runtimeError("null config ptr")
        }
        return config
    }
    
    public func ReadFile(wnfsConfig: WnfsConfig, remotePath: String) throws -> Data? {
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePath = makeCString(from: remotePath)
        
        
        // Needed to deallocate memory in the rust part
        let cLen: UnsafeMutablePointer<Int>? = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        let cCapacity: UnsafeMutablePointer<Int>? = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        let ptr = read_file_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePath, cLen, cCapacity)
        if ptr == nil{
            return nil
        }
        
        let data = toData(ptr: ptr, size: cLen)
        // TODO:
//        cbytes_free(data: ptr, len: cLen?.pointee, capacity: cCapacity?.pointee)
        cLen?.deallocate()
        cCapacity?.deallocate()
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePath)
        return data
    }
    
    public func ReadFileToPath(wnfsConfig: WnfsConfig, remotePath: String, fileUrl: URL) throws -> String? {
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePath = makeCString(from: remotePath)
        let cFilePath = makeCString(from: fileUrl.path)
        
        
        let ptr = read_file_to_path_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePath, cFilePath)
        guard let cFileName = ptr else {
            throw MyError.runtimeError("Empty fileName")
        }
        let fileName = String(cString: cFileName)
        // Freeing the memory
        cstring_free(cFileName)
        
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePath)
        freeCString(cString: cFilePath)
        return fileName
    }
    
    public func ReadFileStreamToPath(wnfsConfig: WnfsConfig, remotePath: String, fileUrl: URL) throws -> String? {
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePath = makeCString(from: remotePath)
        let cFilePath = makeCString(from: fileUrl.path)
        
        
        let ptr = read_filestream_to_path_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePath, cFilePath)
        guard let cFileName = ptr else {
            throw MyError.runtimeError("Empty fileName")
        }
        let fileName = String(cString: cFileName)
        // Freeing the memory
        cstring_free(cFileName)
        
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePath)
        freeCString(cString: cFilePath)
        return fileName
    }
    
    public func MkDir(wnfsConfig: WnfsConfig, remotePath: String) throws -> WnfsConfig{
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePath = makeCString(from: remotePath)
        let ptr = mkdir_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePath)
        
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePath)
        
        guard let config = self.unwrapConfigPtr(ptr: ptr) else{
            throw MyError.runtimeError("null config ptr")
        }
        return config
    }
    
    public func Rm(wnfsConfig: WnfsConfig, remotePath: String) throws -> WnfsConfig {
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePath = makeCString(from: remotePath)
        let ptr = rm_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePath)
        
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePath)
        
        guard let config = self.unwrapConfigPtr(ptr: ptr) else{
            throw MyError.runtimeError("null config ptr")
        }
        return config
    }
    
    public func Cp(wnfsConfig: WnfsConfig, remotePathFrom: String, remotePathTo: String) throws -> WnfsConfig {
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePathFrom = makeCString(from: remotePathFrom)
        let cRemotePathTo = makeCString(from: remotePathTo)
        let ptr = cp_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePathFrom, cRemotePathTo)
        
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePathFrom)
        freeCString(cString: cRemotePathTo)
        
        guard let config = self.unwrapConfigPtr(ptr: ptr) else{
            throw MyError.runtimeError("null config ptr")
        }

        return config
    }
    
    public func Ls(wnfsConfig: WnfsConfig, remotePath: String) throws -> Data? {
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePath = makeCString(from: remotePath)
        
        // Needed to deallocate memory in the rust part
        let cLen: UnsafeMutablePointer<Int>? = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        let cCapacity: UnsafeMutablePointer<Int>? = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        let ptr = ls_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePath, cLen, cCapacity)
        
        if ptr == nil{
            return nil
        }
        
        let data = toData(ptr: ptr, size: cLen)
        
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePath)
        // TODO:
//        cbytes_free(data: ptr, len: cLen?.pointee, capacity: cCapacity?.pointee)
        cLen?.deallocate()
        cCapacity?.deallocate()
        return data
    }
    
    public func Mv(wnfsConfig: WnfsConfig, remotePathFrom: String, remotePathTo: String) throws -> WnfsConfig{
        let cCid = makeCString(from: wnfsConfig.getCid())
        let cPrivateRef = makeCString(from: wnfsConfig.getPrivateRef())
        let cRemotePathFrom = makeCString(from: remotePathFrom)
        let cRemotePathTo = makeCString(from: remotePathTo)
        let ptr = mv_native(self.blockStoreInterface, cCid, cPrivateRef, cRemotePathFrom, cRemotePathTo)
        
        freeCString(cString: cCid)
        freeCString(cString: cPrivateRef)
        freeCString(cString: cRemotePathFrom)
        freeCString(cString: cRemotePathTo)
        
        guard let config = self.unwrapConfigPtr(ptr: ptr) else{
            throw MyError.runtimeError("null config ptr")
        }
        
        return config
    }
    
    
    private func unwrapConfigPtr(ptr: UnsafeMutablePointer<Config>?) -> WnfsConfig? {
        let cid = String(cString: ptr!.pointee.cid!)
        let privateRef = String(cString: ptr!.pointee.private_ref!)
        let c = WnfsConfig(cid: cid, privateRef: privateRef)
        config_free(ptr)
        return c
    }
    
    private func makeCString(from str: String) -> UnsafeMutablePointer<Int8> {
        let count = str.utf8.count + 1
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: count)
        str.withCString { (baseAddress) in
            // func initialize(from: UnsafePointer<Pointee>, count: Int)
            result.initialize(from: baseAddress, count: count)
        }
        
        return result
    }
    
    private func freeCString(cString: UnsafeMutablePointer<Int8>){
        cString.deallocate()
    }
}
