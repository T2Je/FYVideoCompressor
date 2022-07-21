//
//  TestUserDefinedPath.swift
//  FYVideoCompressorTests
//
//  Created by xiaoyang on 2022/7/19.
//

import XCTest
@testable import FYVideoCompressor

class TestUserDefinedPath: XCTestCase {
    static let testVideoURL = URL(string: "https://www.learningcontainer.com/wp-content/uploads/2020/05/sample-mov-file.mov")!
    
    let sampleVideoPath: URL = FileManager.tempDirectory(with: "UnitTestSampleVideo").appendingPathComponent("sample.mp4")
    
    var compressedVideoPath: URL! = URL(fileURLWithPath: "ssssss")
    
    var task: URLSessionDataTask?
    
    let compressor = FYVideoCompressor()
    
    override func setUpWithError() throws {
        let expectation = XCTestExpectation(description: "video cache downloading remote video")
        var error: Error?
        downloadSampleVideo { result in
            switch result {
            case .failure(let _error):
                print("failed to download sample video: \(_error)")
                error = _error
            case .success(let path):
                print("sample video downloaded at path: \(path)")
                expectation.fulfill()
            }
        }
        if let error = error {
            throw error
        }
        wait(for: [expectation], timeout: 100)
    }
    
    override func tearDownWithError() throws {
        task?.cancel()
        try? FileManager.default.removeItem(at: sampleVideoPath)
        try FileManager.default.removeItem(at: compressedVideoPath)
    }

    func testCompressVideo() {
        let expectation = XCTestExpectation(description: "compress video")
                        
        XCTAssertNotNil(compressedVideoPath, "user defined path shouldn't be nil")
        
        compressor.compressVideo(sampleVideoPath, quality: .lowQuality, outputPath: compressedVideoPath) { result in
            switch result {
            case .success(let video):
                self.compressedVideoPath = video
                expectation.fulfill()
            case .failure(let error):
                XCTFail(error.localizedDescription)
            }
        }
        wait(for: [expectation], timeout: 30)
        XCTAssertNotNil(compressedVideoPath)
        XCTAssertTrue(self.sampleVideoPath.sizePerMB() > compressedVideoPath.sizePerMB())
    }
    
    // MARK: Download sample video
    func downloadSampleVideo(_ completion: @escaping ((Result<URL, Error>) -> Void)) {
        if FileManager.default.fileExists(atPath: self.sampleVideoPath.path) {
            completion(.success(self.sampleVideoPath))
        } else {
            request(Self.testVideoURL) { result in
                switch result {
                case .success(let data):
                    do {
                        try (data as NSData).write(to: self.sampleVideoPath, options: NSData.WritingOptions.atomic)
                        completion(.success(self.sampleVideoPath))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func request(_ url: URL, completion: @escaping ((Result<Data, Error>) -> Void)) {
        if task != nil {
            task?.cancel()
        }
        
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                self.task = nil
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.task = nil
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                if let data = data {
                    DispatchQueue.main.async {
                        self.task = nil
                        completion(.success(data))
                    }
                }
            } else {
                let domain = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                let error = NSError(domain: domain, code: httpResponse.statusCode, userInfo: nil)
                DispatchQueue.main.async {
                    self.task = nil
                    completion(.failure(error))
                }
            }
        }
        task.resume()
        self.task = task
    }

}
