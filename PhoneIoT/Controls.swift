//
//  Controls.swift
//  PhoneIoT
//
//  Created by Devin Jean on 3/22/21.
//

import SwiftUI

protocol CustomControl: AnyObject {
    func getID() -> ArraySlice<UInt8>
    func draw(context: CGContext, baseFontSize: CGFloat)
    func contains(pos: CGPoint) -> Bool
    func mouseDown(core: CoreController, pos: CGPoint)
    func mouseMove(core: CoreController, pos: CGPoint)
    func mouseUp(core: CoreController)
}
protocol ToggleLike: CustomControl {
    func getToggleState() -> Bool
}
protocol JoystickLike: CustomControl {
    func getVector() -> (CGFloat, CGFloat)
}
protocol ImageLike: CustomControl {
    func getImage() -> CGImage
    func setImage(_ img: CGImage)
}
protocol TextLike: CustomControl {
    func getText() -> String
    func setText(_ txt: String)
}

// ----------------------------------------------------------------------------------

enum FitType {
    case stretch
    case fit
    case zoom
}
func center(img: CGImage, in rect: CGRect, scale: CGFloat) -> CGRect {
    let oldsize = CGSize(width: img.width, height: img.height)
    let newsize = CGSize(width: oldsize.width * scale, height: oldsize.height * scale)
    return CGRect(
        x: rect.origin.x + (rect.width - newsize.width) / 2,
        y: rect.origin.y + (rect.height - newsize.height) / 2,
        width: newsize.width,
        height: newsize.height
    )
}
func fitRect(for img: CGImage, in rect: CGRect, by fit: FitType) -> CGRect {
    switch fit {
    case .stretch: return rect
    case .fit: return center(img: img, in: rect, scale: min(rect.width / CGFloat(img.width), rect.height / CGFloat(img.height)))
    case .zoom: return center(img: img, in: rect, scale: max(rect.width / CGFloat(img.width), rect.height / CGFloat(img.height)))
    }
}

// this corrects a weird issue where CGImages seem to be drawn upside down
func drawImage(context: CGContext, img: CGImage, in rect: CGRect, clip: CGRect) {
    context.saveGState()
    
    context.clip(to: clip)
    context.translateBy(x: rect.origin.x, y: rect.origin.y + rect.height)
    context.scaleBy(x: 1, y: -1)
    context.draw(img, in: CGRect(origin: .zero, size: rect.size))
    
    context.restoreGState()
}

func drawString(_ text: String, in rect: CGRect, context: CGContext, fontSize: CGFloat, align: NSTextAlignment, color: CGColor, centerY: Bool) {
    let font = UIFont.systemFont(ofSize: fontSize)
    let par = NSMutableParagraphStyle()
    par.alignment = align
    par.lineBreakMode = .byWordWrapping
    let str = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: par, .strokeColor: color, .foregroundColor: color])
    let oversize = CGSize(width: rect.width, height: rect.height + fontSize) // over-draw a line (will be clipped later)
    let bound = str.boundingRect(with: oversize, options: .usesLineFragmentOrigin, context: nil)
    
    let boundHeightClipped = min(bound.height, rect.height) // get the clipped size
    var xshift: CGFloat = 0 // if text is small, alignment doesn't actually come into play - fix this
    if align == .center { xshift = (rect.width - bound.width) / 2 }
    else if align == .right { xshift = rect.width - bound.width }
    
    let pos = CGPoint(x: rect.origin.x + xshift, y: rect.origin.y + (centerY ? (rect.height - boundHeightClipped) / 2 : 0))
    
    UIGraphicsPushContext(context)
    context.saveGState()
    context.clip(to: CGRect(origin: pos, size: CGSize(width: bound.width, height: boundHeightClipped)))
    str.draw(with: CGRect(origin: pos, size: bound.size), options: .usesLineFragmentOrigin, context: nil)
    context.restoreGState()
    UIGraphicsPopContext()
}

// ------------------------------------------------------------------------------------

class CustomLabel: CustomControl, TextLike {
    private var pos: CGPoint
    private var textColor: CGColor
    private var id: [UInt8]
    private var text: String
    private var fontSize: CGFloat
    private var align: NSTextAlignment
    private var landscape: Bool
    
    init(x: CGFloat, y: CGFloat, textColor: CGColor, id: [UInt8], text: String, fontSize: CGFloat, align: NSTextAlignment, landscape: Bool) {
        self.pos = CGPoint(x: x, y: y)
        self.textColor = textColor
        self.id = id
        self.text = text
        self.fontSize = fontSize
        self.align = align
        self.landscape = landscape
    }
    
    func getID() -> ArraySlice<UInt8> {
        id[...]
    }
    func draw(context: CGContext, baseFontSize: CGFloat) {
        context.saveGState()
        context.translateBy(x: pos.x, y: pos.y)
        if landscape { context.rotate(by: .pi / 2) }
        
        let font = UIFont.systemFont(ofSize: baseFontSize * fontSize)
        let par = NSMutableParagraphStyle()
        par.alignment = .center
        let str = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: par, .strokeColor: textColor, .foregroundColor: textColor])
        let bound = str.boundingRect(with: CGSize(width: CGFloat.infinity, height: .infinity), options: .usesLineFragmentOrigin, context: nil)
        
        var p: CGPoint = .zero
        switch align {
        case .right: p.x -= bound.width
        case .center: p.x -= bound.width / 2
        default: break
        }
        
        UIGraphicsPushContext(context)
        str.draw(with: CGRect(origin: p, size: bound.size), options: .usesLineFragmentOrigin, context: nil)
        UIGraphicsPopContext()
        
        context.restoreGState()
    }
    
    func contains(pos: CGPoint) -> Bool { false }
    func mouseDown(core: CoreController, pos: CGPoint) { }
    func mouseMove(core: CoreController, pos: CGPoint) { }
    func mouseUp(core: CoreController) { }
    
    func getText() -> String {
        text
    }
    func setText(_ txt: String) {
        text = txt
    }
}

enum ButtonStyle {
    case Rectangle
    case Ellipse
}
class CustomButton: CustomControl, ToggleLike, TextLike {
    private var rect: CGRect
    private var color: CGColor
    private var textColor: CGColor
    private var id: [UInt8]
    private var text: String
    private var fontSize: CGFloat
    private var style: ButtonStyle
    private var landscape: Bool
    
    private var pressed = false
    
    private static let padding: CGFloat = 5
    private static let pressColor = CGColor(gray: 1.0, alpha: 100.0 / 255)
    
    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: CGColor, textColor: CGColor, id: [UInt8], text: String, fontSize: CGFloat, style: ButtonStyle, landscape: Bool) {
        self.rect = CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
        self.color = color
        self.textColor = textColor
        self.id = id
        self.text = text
        self.fontSize = fontSize
        self.style = style
        self.landscape = landscape
    }
    
    func getID() -> ArraySlice<UInt8> { id[...] }
    func fillRegion(context: CGContext, rect: CGRect) {
        switch style {
        case .Rectangle: context.fill(rect)
        case .Ellipse: context.fillEllipse(in: rect)
        }
    }
    func draw(context: CGContext, baseFontSize: CGFloat) {
        context.saveGState()
        context.translateBy(x: rect.origin.x, y: rect.origin.y)
        if landscape { context.rotate(by: .pi / 2) }
        
        let mainRect = CGRect(origin: .zero, size: rect.size)
        context.setFillColor(color)
        fillRegion(context: context, rect: mainRect)
        
        let textRect = CGRect(
            origin: CGPoint(x: Self.padding, y: Self.padding),
            size: CGSize(width: rect.size.width - 2 * Self.padding, height: rect.size.height - 2 * Self.padding))
        drawString(text, in: textRect, context: context, fontSize: baseFontSize * fontSize, align: .center, color: textColor, centerY: true)
        
        if pressed {
            context.setFillColor(Self.pressColor)
            fillRegion(context: context, rect: mainRect)
        }
        
        context.restoreGState()
    }
    
    func contains(pos: CGPoint) -> Bool {
        let r = landscape ? rotate(rect: rect) : rect
        
        switch style {
        case .Rectangle: return r.contains(pos)
        case .Ellipse: return ellipseContains(ellipse: r, point: pos)
        }
    }
    func mouseDown(core: CoreController, pos: CGPoint) {
        pressed = true
        core.send(core.netsbloxify([ UInt8(ascii: "b") ] + id))
    }
    func mouseMove(core: CoreController, pos: CGPoint) { }
    func mouseUp(core: CoreController) {
        pressed = false
    }
    
    func getToggleState() -> Bool {
        pressed
    }
    
    func getText() -> String {
        text
    }
    func setText(_ txt: String) {
        text = txt
    }
}

class CustomTextField: CustomControl, TextLike {
    private var rect: CGRect
    private var color: CGColor
    private var textColor: CGColor
    private var id: [UInt8]
    private var text: String
    private var readonly: Bool
    private var fontSize: CGFloat
    private var align: NSTextAlignment
    private var landscape: Bool
    
    private static let strokeWidth: CGFloat = 2
    private static let padding: CGFloat = 10
    
    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: CGColor, textColor: CGColor, id: [UInt8], text: String, readonly: Bool, fontSize: CGFloat, align: NSTextAlignment, landscape: Bool) {
        self.rect = CGRect(x: x, y: y, width: width, height: height)
        self.color = color
        self.textColor = textColor
        self.id = id
        self.text = text
        self.readonly = readonly
        self.fontSize = fontSize
        self.align = align
        self.landscape = landscape
    }
    
    func getID() -> ArraySlice<UInt8> {
        id[...]
    }
    func draw(context: CGContext, baseFontSize: CGFloat) {
        context.saveGState()
        context.translateBy(x: rect.origin.x, y: rect.origin.y)
        if landscape { context.rotate(by: .pi / 2) }
        
        let mainRect = CGRect(origin: .zero, size: rect.size)
        context.setStrokeColor(color)
        context.stroke(mainRect, width: Self.strokeWidth)
        
        let textRect = CGRect(
            origin: CGPoint(x: Self.padding, y: Self.padding),
            size: CGSize(width: mainRect.size.width - 2 * Self.padding, height: mainRect.size.height - Self.padding)) // don't pad bottom
        drawString(text, in: textRect, context: context, fontSize: baseFontSize * fontSize, align: align, color: textColor, centerY: false)
        
        context.restoreGState()
    }
    func contains(pos: CGPoint) -> Bool {
        let r = landscape ? rotate(rect: rect) : rect
        return r.contains(pos)
    }
    func mouseDown(core: CoreController, pos: CGPoint) { }
    func mouseMove(core: CoreController, pos: CGPoint) { }
    func mouseUp(core: CoreController) { }
    
    func getText() -> String {
        text
    }
    func setText(_ txt: String) {
        text = txt
    }
}

class CustomImageDisplay: CustomControl, ImageLike {
    private var rect: CGRect
    private var id: [UInt8]
    private var img: CGImage
    private var readonly: Bool
    private var landscape: Bool
    private var fit: FitType

    private static let fillColor = CGColor(gray: 0, alpha: 1)
    private static let strokeColor = fillColor
    private static let strokeWidth: CGFloat = 2

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, id: [UInt8], readonly: Bool, landscape: Bool, fit: FitType) {
        self.rect = CGRect(x: x, y: y, width: width, height: height)
        self.id = id
        self.img = cgImage(uiImage: defaultImage(color: Self.fillColor))!
        self.readonly = readonly
        self.landscape = landscape
        self.fit = fit
    }

    func getID() -> ArraySlice<UInt8> {
        self.id[...]
    }
    func draw(context: CGContext, baseFontSize: CGFloat) {
        context.saveGState()
        context.translateBy(x: rect.origin.x, y: rect.origin.y)
        if landscape { context.rotate(by: .pi / 2) }

        let mainRect = CGRect(origin: .zero, size: rect.size)
        context.setFillColor(Self.fillColor)
        context.fill(mainRect)
        
        let imgRect = fitRect(for: img, in: mainRect, by: fit)
        drawImage(context: context, img: img, in: imgRect, clip: mainRect)

        context.setStrokeColor(Self.strokeColor)
        context.stroke(mainRect, width: Self.strokeWidth)

        context.restoreGState()
    }

    func contains(pos: CGPoint) -> Bool {
        let r = landscape ? rotate(rect: rect) : rect
        return r.contains(pos)
    }
    func mouseDown(core: CoreController, pos: CGPoint) { }
    func mouseMove(core: CoreController, pos: CGPoint) { }
    func mouseUp(core: CoreController) { }
    
    func getImage() -> CGImage {
        img
    }
    func setImage(_ img: CGImage) {
        self.img = img
    }
}
