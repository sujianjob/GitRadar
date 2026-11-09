#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let fileManager = FileManager.default
let resourcesDir = URL(fileURLWithPath: "Resources")
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")
let pngPreviewPath = resourcesDir.appendingPathComponent("AppIcon.png")

try? fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
try? fileManager.removeItem(at: iconsetDir)
try fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func drawIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let s = CGFloat(size)
    let pad = s * 0.08
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let corner = rect.width * 0.225

    // 1. 圆角深色雷达背景
    let bgPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 1.0),
        CGColor(red: 0.09, green: 0.18, blue: 0.32, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    let center = CGPoint(x: s * 0.5, y: s * 0.5)

    // 2. 雷达扫描扇形光晕
    ctx.saveGState()
    ctx.move(to: center)
    ctx.addArc(
        center: center,
        radius: rect.width * 0.42,
        startAngle: .pi * 0.12,
        endAngle: .pi * 0.55,
        clockwise: false
    )
    ctx.closePath()
    ctx.setFillColor(CGColor(red: 0.15, green: 0.82, blue: 0.65, alpha: 0.26))
    ctx.fillPath()
    ctx.restoreGState()

    // 3. 同心雷达圆环
    for factor in [0.16, 0.28, 0.40] {
        let r = rect.width * CGFloat(factor)
        let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.78, blue: 0.95, alpha: 0.28))
        ctx.setLineWidth(max(1.5, s * 0.008))
        ctx.strokeEllipse(in: ringRect)
    }

    // 4. 绘制 Git 分支拓扑线条与节点
    let pMainBottom = CGPoint(x: s * 0.38, y: s * 0.28)
    let pMainMid = CGPoint(x: s * 0.38, y: s * 0.50)
    let pMainTop = CGPoint(x: s * 0.38, y: s * 0.72)
    let pBranchNode = CGPoint(x: s * 0.64, y: s * 0.62)

    ctx.setStrokeColor(CGColor(red: 0.24, green: 0.88, blue: 0.72, alpha: 0.95))
    ctx.setLineWidth(max(2.0, s * 0.036))
    ctx.setLineCap(.round)

    // 主干线
    ctx.move(to: pMainBottom)
    ctx.addLine(to: pMainTop)
    ctx.strokePath()

    // 分支曲线
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.68, blue: 1.0, alpha: 0.95))
    ctx.move(to: pMainMid)
    ctx.addCurve(
        to: pBranchNode,
        control1: CGPoint(x: s * 0.38, y: s * 0.60),
        control2: CGPoint(x: s * 0.52, y: s * 0.62)
    )
    ctx.strokePath()

    // 节点圆点
    let nodes: [(CGPoint, CGColor)] = [
        (pMainBottom, CGColor(red: 0.24, green: 0.88, blue: 0.72, alpha: 1.0)),
        (pMainMid, CGColor(red: 0.24, green: 0.88, blue: 0.72, alpha: 1.0)),
        (pMainTop, CGColor(red: 0.24, green: 0.88, blue: 0.72, alpha: 1.0)),
        (pBranchNode, CGColor(red: 1.0, green: 0.62, blue: 0.22, alpha: 1.0))
    ]
    let nodeR = s * 0.048
    for (pt, color) in nodes {
        let nr = CGRect(x: pt.x - nodeR, y: pt.y - nodeR, width: nodeR * 2, height: nodeR * 2)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: nr)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(max(1.5, s * 0.012))
        ctx.strokeEllipse(in: nr)
    }

    ctx.restoreGState()

    // 5. 外框高光描边
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 0.45, green: 0.80, blue: 1.0, alpha: 0.35))
    ctx.setLineWidth(max(1.5, s * 0.01))
    ctx.strokePath()

    img.unlockFocus()
    return img
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        return
    }
    try png.write(to: url)
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, filename) in sizes {
    let icon = drawIcon(size: px)
    try savePNG(icon, to: iconsetDir.appendingPathComponent(filename))
    if px == 512 && filename == "icon_512x512.png" {
        try savePNG(icon, to: pngPreviewPath)
    }
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try proc.run()
proc.waitUntilExit()
try? fileManager.removeItem(at: iconsetDir)
print("✅ 已生成 Resources/AppIcon.icns")
