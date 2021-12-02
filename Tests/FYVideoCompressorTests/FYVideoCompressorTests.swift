import XCTest
@testable import FYVideoCompressor
import AVFoundation

final class FYVideoCompressorTests: XCTestCase {
    static let testVideoURL = URL(string: "http://clips.vorwaerts-gmbh.de/VfE_html5.mp4")!
    
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
    }
    
    func testAVFileTypeExtension() {
        let mp4Extension = AVFileType("public.mpeg-4")
        XCTAssertEqual(mp4Extension.fileExtension, "mp4")
        
        let movExtension = AVFileType("com.apple.quicktime-movie")
        XCTAssertEqual(movExtension.fileExtension, "mov")
    }
}
