//
//  FileLogger.swift
//  GDPerformanceView-Swift
//
//  Created by Steven Chen on 2022/1/4.
//  Copyright © 2022 Daniil Gavrilov. All rights reserved.
//

import Foundation

final internal class FileLogger {
    private let url: URL
    init(with fileUrl:URL) {
        try? FileManager.default.removeItem(atPath: fileUrl.path)
        url = fileUrl
    }
    
    func log(_ message: String) {
        do {
            try message.appendLineToURL(fileURL: url as URL)
        } catch {
            print("log file failed.")
        }
    }
}

extension String {
    func appendLineToURL(fileURL: URL) throws {
         try (self + "\n").appendToURL(fileURL: fileURL)
     }

     func appendToURL(fileURL: URL) throws {
         let data = self.data(using: String.Encoding.utf8)!
         try data.append(fileURL: fileURL)
     }
 }

extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        }
        else {
            try write(to: fileURL, options: .atomic)
        }
     }
}
