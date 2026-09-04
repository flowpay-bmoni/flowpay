import Foundation
import PDFKit
import CoreGraphics

let pdfURL = URL(fileURLWithPath: "/Users/macbookpro/flowpay/deck/FlowPay_Pitch_Deck.pdf")
guard let document = PDFDocument(url: pdfURL) else {
    print("Could not open PDF")
    exit(1)
}

let outputDir = "/Users/macbookpro/flowpay/deck/preview_pages"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for i in 0..<document.pageCount {
    guard let page = document.page(at: i) else { continue }
    let pageRect = page.bounds(for: .mediaBox)
    let scale: CGFloat = 1.0 // 1152x648
    let width = Int(pageRect.width * scale)
    let height = Int(pageRect.height * scale)
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
        continue
    }
    
    context.setFillColor(CGColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
    
    if let image = context.makeImage() {
        let destURL = URL(fileURLWithPath: "\(outputDir)/slide_\(i+1).png") as CFURL
        guard let destination = CGImageDestinationCreateWithURL(destURL, "public.png" as CFString, 1, nil) else { continue }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("Rendered slide \(i+1)")
    }
}
