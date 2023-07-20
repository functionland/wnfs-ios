//
//  Test.swift
//
//  Created by Homayoun on 1/16/23.
//
import func XCTest.XCTAssertEqual
import Foundation
import XCTest
import CryptoKit
import CID
import Multihash
import Multicodec
@testable import WnfsSwift

class MockSession {

    static let sharedInstance = MockSession()

    var myData = Dictionary<Data,Data>()
}

public func mockFulaGet(_ cid: Data?) -> Data? {

    if let data = MockSession.sharedInstance.myData[cid!] {
        return data
    }
    return nil
}

public func mockFulaPut(_ data: Data?, _ _codec: Int64) -> Data? {
    let codec: Codecs
    do{
        codec = try Codecs(_codec)
    } catch let error{
        print(error.localizedDescription)
        return nil
    }
    let hash: Multihash
    let cid: CID
    do{
        hash = try Multihash(raw: data!, hashedWith: .sha2_256)
    } catch let error{
        print(error.localizedDescription)
        return nil
    }
    do{
        cid = try CID(version: .v1, codec: codec, multihash: hash)
    } catch let error{
        print(error.localizedDescription)
        return nil
    }

    MockSession.sharedInstance.myData[cid.rawData] = data!
    print(cid.toBaseEncodedString)
    print(cid.rawData.toHexString())
    return Data(cid.rawData)
}

final class WnfsSwiftTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCID() throws {
        let mh = try Multihash(raw: "abc", hashedWith: .sha2_256)
        let cid = try CID(version: .v1, codec: .dag_cbor, multihash: mh)

        assert(cid.toBaseEncodedString == "bafyreif2pall7dybz7vecqka3zo24irdwabwdi4wc55jznaq75q7eaavvu")
        let cid_recreated = try CID(cid.rawData.bytes)
        assert(cid_recreated.toBaseEncodedString == cid.toBaseEncodedString)
    }
    
    func testOverall() throws {
        let wnfsWrapper = WnfsWrapper(putFn: mockFulaPut, getFn: mockFulaGet)
        var wnfsConfig = try wnfsWrapper.CreatePrivateForest(wnfsKey: "test")
        
        let data = "hello, world!".data(using: .utf8)!
        wnfsConfig = try wnfsWrapper.WriteFile(wnfsConfig: wnfsConfig, remotePath: "/root/file.txt", data: data)
        assert(wnfsConfig.getCid() != "")
        assert(wnfsConfig.getPrivateRef() != "")
        print("cid: " + wnfsConfig.getCid())
        print("private ref: " + wnfsConfig.getPrivateRef())
        
        let content = try wnfsWrapper.ReadFile(wnfsConfig: wnfsConfig, remotePath: "/root/file.txt")
        assert(content != nil)
        let str = String(decoding: content!, as: UTF8.self)
        assert(str == "hello, world!")
        
        let file = "file.txt" //this is the file. we will write to and read from it
        let text = "hello, world!" //just a text
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent(file)
            //writing
            do {
                try text.write(to: fileURL, atomically: false, encoding: .utf8)
            }
            catch {/* error handling here */}
            wnfsConfig = try wnfsWrapper.WriteFileFromPath(wnfsConfig: wnfsConfig, remotePath: "/root/filefrompath.txt", fileUrl: fileURL)
            let content = try wnfsWrapper.ReadFile(wnfsConfig: wnfsConfig, remotePath: "/root/filefrompath.txt")
            assert(content != nil)
            let str = String(decoding: content!, as: UTF8.self)
            assert(str == "hello, world!")
        }
        
        wnfsConfig = try wnfsWrapper.MkDir(wnfsConfig: wnfsConfig, remotePath: "/root/dir1/")
        wnfsConfig = try wnfsWrapper.Cp(wnfsConfig: wnfsConfig, remotePathFrom: "/root/file.txt", remotePathTo: "/root/dir1/file.txt")
        let lsResult = try wnfsWrapper.Ls(wnfsConfig: wnfsConfig, remotePath: "/root/dir1")
        let lsResultStr = String(decoding: lsResult!, as: UTF8.self)
        assert(lsResultStr.hasPrefix("file.txt"))
        
        wnfsConfig = try wnfsWrapper.Mv(wnfsConfig: wnfsConfig, remotePathFrom: "/root/file.txt", remotePathTo: "/root/file1.txt")
        let content2 = try wnfsWrapper.ReadFile(wnfsConfig: wnfsConfig, remotePath: "/root/file.txt")
        assert(content2 != nil)
        let str2 = String(decoding: content2!, as: UTF8.self)
        assert(str2 == "")

        wnfsConfig = try wnfsWrapper.Rm(wnfsConfig: wnfsConfig, remotePath: "/root/dir1")
        let content3 = try wnfsWrapper.ReadFile(wnfsConfig: wnfsConfig, remotePath: "/root/dir1/file.txt")
        assert(content3 != nil)
        let str3 = String(decoding: content3!, as: UTF8.self)
        assert(str3 == "")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.+9-
        }
    }
}
