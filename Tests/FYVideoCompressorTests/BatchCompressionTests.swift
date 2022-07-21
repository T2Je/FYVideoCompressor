//
//  BatchCompressionTests.swift
//  FYVideoCompressorTests
//
//  Created by xiaoyang on 2022/6/17.
//

import XCTest
import FYVideoCompressor

class BatchCompressionTests: XCTestCase {

//    "http://clips.vorwaerts-gmbh.de/VfE_html5.mp4"
    let sampleVideoURLs = [
        "https://www.learningcontainer.com/wp-content/uploads/2020/05/sample-mov-file.mov",
        "https://www.learningcontainer.com/wp-content/uploads/2020/05/sample-mp4-file.mp4",
        "http://clips.vorwaerts-gmbh.de/VfE_html5.mp4"
    ]

    var sampleVideoPath: [URL: URL] = [:]
    var compressedVideoPath: [URL: URL] = [:]
    
    var tasks: [URL: URLSessionDataTask] = [:]
    
    func setupSampleVideoPath() {
        sampleVideoURLs.forEach { urlStr in
            if let url = URL(string: urlStr) {
                sampleVideoPath[url] = FileManager.tempDirectory(with: "UnitTestSampleVideo").appendingPathComponent("\(url.lastPathComponent)")
            }
        }
    }
    
    override func setUpWithError() throws {
        setupSampleVideoPath()
        let expectation = XCTestExpectation(description: "video cache downloading remote video")
        var error: Error?
        
        var allSampleVideosCount = sampleVideoPath.count
        
        sampleVideoURLs.forEach { urlStr in
            downloadSampleVideo(URL(string: urlStr)!) { result in
                switch result {
                case .failure(let _error):
                    print("💀failed to download sample video:(\(urlStr)) with error: \(_error)")
                    error = _error
                case .success(let path):
                    print("sample video downloaded at path: \(path)")
                    allSampleVideosCount -= 1
                    if allSampleVideosCount <= 0 {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        if let error = error {
            throw error
        }
        wait(for: [expectation], timeout: 300)
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        tasks.values.forEach {
            $0.cancel()
        }
        sampleVideoPath.values.forEach {
            try? FileManager.default.removeItem(at: $0)
        }

        compressedVideoPath.values.forEach {
            try? FileManager.default.removeItem(at: $0)
        }
    }
    
    func testCompressVideo() {
        let expectation = XCTestExpectation(description: "compress video")
                    
        var allSampleVideosCount = sampleVideoPath.count
        
        sampleVideoPath.values.forEach { sampleVideo in
            FYVideoCompressor.shared.compressVideo(sampleVideo, quality: .lowQuality) { result in
                switch result {
                case .success(let video):
                    self.compressedVideoPath[sampleVideo] = video
                    
                    allSampleVideosCount -= 1
                    if allSampleVideosCount <= 0 {
                        expectation.fulfill()
                    }
                case .failure(let error):
                    XCTFail(error.localizedDescription)
                }
            }
        }
        
        wait(for: [expectation], timeout: 300)
        XCTAssertNotNil(compressedVideoPath)
//        XCTAssertTrue(self.sampleVideoPath.sizePerMB() > compressedVideoPath!.sizePerMB())
    }
    

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    // MARK: Download sample video
    func downloadSampleVideo(_ url: URL, _ completion: @escaping ((Result<URL, Error>) -> Void)) {
        let sampleVideoCachedURL: URL
        if let path = sampleVideoPath[url] {
            sampleVideoCachedURL = path
        } else {
            sampleVideoCachedURL = FileManager.tempDirectory(with: "UnitTestSampleVideo").appendingPathComponent("\(url.lastPathComponent)")
            sampleVideoPath[url] = sampleVideoCachedURL
        }
        if FileManager.default.fileExists(atPath: sampleVideoCachedURL.absoluteString) {
            completion(.success(sampleVideoCachedURL))
        } else {
            request(url) { result in
                switch result {
                case .success(let data):
                    do {
                        try (data as NSData).write(to: sampleVideoCachedURL, options: NSData.WritingOptions.atomic)
                        completion(.success(sampleVideoCachedURL))
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
        tasks[url]?.cancel()
        print("Donwloading \(url.absoluteString)")
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                self.tasks[url] = nil
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.tasks[url] = nil
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                if let data = data {
                    DispatchQueue.main.async {
                        self.tasks[url] = nil
                        completion(.success(data))
                    }
                }
            } else {
                let domain = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                let error = NSError(domain: domain, code: httpResponse.statusCode, userInfo: nil)
                DispatchQueue.main.async {
                    self.tasks[url] = nil
                    completion(.failure(error))
                }
            }
        }
        task.resume()
        self.tasks[url] = task
    }
}
