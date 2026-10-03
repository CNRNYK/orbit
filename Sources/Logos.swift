import AppKit
import SwiftUI
import ImageIO

/// Official-site icons are bundled for offline use and refreshed without blocking launch.
@MainActor final class LogoStore: ObservableObject {
    static let shared = LogoStore()
    @Published private(set) var images: [String: NSImage] = [:]
    private var started = false
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("io.macsetup.desktop/Logos", isDirectory: true)
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = ["User-Agent": "Orbit/0.5"]
        return URLSession(configuration: configuration)
    }()
    static func decode(_ data: Data) -> NSImage? {
        guard data.count <= 1_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    func image(for package: Package) -> NSImage? {
        if let image = images[package.id] { return image }
        guard let name = package.logoFilename else { return nil }
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Logos/" + name)
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Logos/" + name)
        for file in [cache.appendingPathComponent(name), bundled] {
            if let data = try? Data(contentsOf: file), let image = Self.decode(data) { return image }
        }
        return nil
    }
    func start() async {
        guard !started else { return }; started = true
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let packages = Catalog.packages.filter { $0.officialLogoURL != nil && $0.logoFilename != nil }
        // Four workers limit launch-time network traffic. A fresh disk cache is reused for 30 days.
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<4 {
                group.addTask { @MainActor in
                    for index in stride(from: worker, to: packages.count, by: 4) {
                        if Task.isCancelled { return }
                        await self.refresh(packages[index])
                    }
                }
            }
        }
    }
    private func refresh(_ package: Package) async {
        guard let url = package.officialLogoURL, let name = package.logoFilename else { return }
        let file = cache.appendingPathComponent(name)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
           let date = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < 30 * 86400,
           let data = try? Data(contentsOf: file), let image = Self.decode(data) {
            images[package.id] = image; return
        }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.scheme == "https", response.expectedContentLength <= 1_000_000 else { return }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_000_000, !Task.isCancelled else { return }
                data.append(byte)
            }
            guard let image = Self.decode(data) else { return }
            try? data.write(to: file, options: .atomic)
            images[package.id] = image
        } catch { /* Bundled and local icons remain available when offline. */ }
    }
}

struct OrbitBrandIcon: View {
    var size: CGFloat = 30
    private static let image: NSImage? = Bundle.main.url(forResource: "Orbit", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        Group {
            if let image = Self.image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "circle.circle").resizable().scaledToFit() }
        }.frame(width: size, height: size).accessibilityLabel("Orbit logo")
    }
}
