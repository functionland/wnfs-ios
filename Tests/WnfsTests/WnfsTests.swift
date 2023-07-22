//
//  Test.swift
//
//  Created by Homayoun on 1/16/23.
//
import func XCTest.XCTAssertEqual
import Foundation
import XCTest
import CryptoKit
@testable import Wnfs

class MockSession {

    static let sharedInstance = MockSession()

    var myData = Dictionary<Data,Data>()
}

public func mockFulaGet(_ cid: Data) throws-> Data {

    if let data = MockSession.sharedInstance.myData[cid] {
        return data
    }
    throw MyError.runtimeError("data not found")
}

public func mockFulaPut(_ cid: Data, _ data: Data) throws->Void  {
    MockSession.sharedInstance.myData[cid] = data
}

final class WnfsSwiftTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }


    func testOverall() throws {
        let wnfs = Wnfs(putFn: mockFulaPut, getFn: mockFulaGet)
        var cid = try wnfs.Init(wnfsKey: "test")
        
        let data = "hello, world!".data(using: .utf8)!
        cid = try wnfs.WriteFile(cid: cid, remotePath: "/root/file.txt", data: data)
        assert(cid != "")
        print("cid: " + cid)

        let content = try wnfs.ReadFile(cid: cid, remotePath: "/root/file.txt")
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
            cid = try wnfs.WriteFileFromPath(cid: cid, remotePath: "/root/filefrompath.txt", fileUrl: fileURL)
            let content = try wnfs.ReadFile(cid: cid, remotePath: "/root/filefrompath.txt")
            assert(content != nil)
            let str = String(decoding: content!, as: UTF8.self)
            assert(str == "hello, world!")
        }
        
        cid = try wnfs.MkDir(cid: cid, remotePath: "/root/dir1/")
        cid = try wnfs.Cp(cid: cid, remotePathFrom: "/root/file.txt", remotePathTo: "/root/dir1/file.txt")
        let lsResult = try wnfs.Ls(cid: cid, remotePath: "/root/dir1")
        let lsResultStr = String(decoding: lsResult!, as: UTF8.self)
        assert(lsResultStr.hasPrefix("file.txt"))
        
        cid = try wnfs.Mv(cid: cid, remotePathFrom: "/root/file.txt", remotePathTo: "/root/file1.txt")
        let content2 = try wnfs.ReadFile(cid: cid, remotePath: "/root/file.txt")
        assert(content2 != nil)
        let str2 = String(decoding: content2!, as: UTF8.self)
        assert(str2 == "")

        cid = try wnfs.Rm(cid: cid, remotePath: "/root/dir1")
        let content3 = try wnfs.ReadFile(cid: cid, remotePath: "/root/dir1/file.txt")
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
