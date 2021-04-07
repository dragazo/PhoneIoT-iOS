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
    func setToggleState(_ state: Bool)
}
protocol PushLike: CustomControl {
    func isPushed() -> Bool
}
protocol JoystickLike: CustomControl {
    func getJoystick() -> CGPoint
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
    case stretch, fit, zoom
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
class CustomButton: CustomControl, TextLike, PushLike {
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
    
    func isPushed() -> Bool {
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
    func mouseDown(core: CoreController, pos: CGPoint) {
        if !readonly {
            core.editText = text
            core.editTextTarget = self
            core.showEditText = true
        }
    }
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

class CustomJoystick: CustomControl, JoystickLike {
    private var rect: CGRect
    private var color: CGColor
    private var id: [UInt8]
    private var landscape: Bool
    
    private static let strokeWidthRatio: CGFloat = 0.035
    private static let stickSize: CGFloat = 0.3333
    
    private var stick: CGPoint = .zero
    
    private var lastUpdate = Date()
    private static let updateInterval: Double = 0.1
    private var updateCount: UInt32 = 0
    
    init(x: CGFloat, y: CGFloat, r: CGFloat, color: CGColor, id: [UInt8], landscape: Bool) {
        self.rect = CGRect(x: x, y: y, width: r, height: r)
        self.color = color
        self.id = id
        self.landscape = landscape
    }
    
    func getID() -> ArraySlice<UInt8> {
        id[...]
    }
    func draw(context: CGContext, baseFontSize: CGFloat) {
        context.setStrokeColor(color)
        context.setLineWidth(rect.width * Self.strokeWidthRatio)
        context.strokeEllipse(in: rect)
        
        let cgstick = CGPoint(
            x: rect.origin.x + (stick.x + 1 - Self.stickSize) * (rect.width / 2),
            y: rect.origin.y + (stick.y + 1 - Self.stickSize) * (rect.width / 2)
        )
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(origin: cgstick, size: CGSize(width: rect.width * Self.stickSize, height: rect.width * Self.stickSize)))
    }
    
    func updateStick(core: CoreController, point: CGPoint) {
        let radius = rect.width / 2
        var x = point.x - (rect.origin.x + radius)
        var y = point.y - (rect.origin.y + radius)
        let dist = sqrt(x * x + y * y)
        if dist > radius { // if it's too far away, point in the right direction but put it in bounds
            x *= radius / dist
            y *= radius / dist
        }
        stick = CGPoint(x: x / radius, y: y / radius)
        
        let now = Date()
        if now.timeIntervalSince(lastUpdate) >= Self.updateInterval { // throttle events since we're way faster than the server
            lastUpdate = now
            sendEvent(core: core)
        }
    }
    func sendEvent(core: CoreController) {
        let x = landscape ? stick.y : stick.x
        let y = landscape ? stick.x : -stick.y
        core.send(core.netsbloxify([ UInt8(ascii: "K") ] + toBEBytes(u32: updateCount) + toBEBytes(cgf32: x) + toBEBytes(cgf32: y) + id))
        updateCount += 1
    }
    
    func contains(pos: CGPoint) -> Bool {
        ellipseContains(ellipse: rect, point: pos)
    }
    func mouseDown(core: CoreController, pos: CGPoint) {
        updateStick(core: core, point: pos)
    }
    func mouseMove(core: CoreController, pos: CGPoint) {
        updateStick(core: core, point: pos)
    }
    func mouseUp(core: CoreController) {
        stick = .zero
        sendEvent(core: core) // make sure we definitely send this last event
    }
    
    func getJoystick() -> CGPoint {
        stick
    }
}

enum ToggleStyle {
    case checkbox, toggleswitch
}
class CustomToggle: CustomControl, ToggleLike, TextLike {
    private var pos: CGPoint
    private var checkColor: CGColor
    private var textColor: CGColor
    private var checked: Bool
    private var id: [UInt8]
    private var text: String
    private var style: ToggleStyle
    private var fontSize: CGFloat
    private var landscape: Bool
    private var readonly: Bool
    
    private var box: CGSize = .zero
    
    private static let uncheckedColor = CGColor(gray: 0.85, alpha: 1)
    
    private static let strokeWidth: CGFloat = 4
    
    private static let checkboxSize: CGFloat = 1
    
    private static let toggleswitchWidth: CGFloat = 2.5
    private static let toggleswitchHeight: CGFloat = 1.5
    
    private static let textPadding: CGFloat = 25
    private static let clickPadding: CGFloat = 20
    
    init(x: CGFloat, y: CGFloat, checkColor: CGColor, textColor: CGColor, checked: Bool, id: [UInt8], text: String, style: ToggleStyle, fontSize: CGFloat, landscape: Bool, readonly: Bool) {
        self.pos = CGPoint(x: x, y: y)
        self.checkColor = checkColor
        self.textColor = textColor
        self.checked = checked
        self.id = id
        self.text = text
        self.style = style
        self.fontSize = fontSize
        self.landscape = landscape
        self.readonly = readonly
    }
    
    func getID() -> ArraySlice<UInt8> {
        id[...]
    }
    func drawCheckbox(context: CGContext, size: CGFloat) {
        let w = size * Self.checkboxSize
        box = CGSize(width: w, height: w)
        let rect = CGRect(origin: .zero, size: box)
        
        context.setStrokeColor(checked ? checkColor : Self.uncheckedColor)
        
        context.stroke(rect, width: Self.strokeWidth)
        if checked {
            context.beginPath()
            context.move(to: CGPoint(x: w / 4, y: w / 2))
            context.addLine(to: CGPoint(x: w / 2, y: 3 * w / 4))
            context.addLine(to: CGPoint(x: w, y: -w / 2))
            
            context.setLineWidth(Self.strokeWidth)
            context.strokePath()
        }
    }
    func drawToggleswitch(context: CGContext, size: CGFloat) {
        let w = size * Self.toggleswitchWidth
        let h = size * Self.toggleswitchHeight
        box = CGSize(width: w, height: h)
        
        context.setFillColor(checked ? checkColor : Self.uncheckedColor)
        
        context.beginPath()
        context.move(to: CGPoint(x: h / 2, y: 0))
        context.addLine(to: CGPoint(x: w - h / 2, y: 0))
        context.move(to: CGPoint(x: h / 2, y: h))
        context.addLine(to: CGPoint(x: w - h / 2, y: h))
        context.addArc(center: CGPoint(x: h / 2, y: h / 2), radius: h / 2, startAngle: .pi / 2, endAngle: .pi * 3 / 2, clockwise: false)
        context.addArc(center: CGPoint(x: w - h / 2, y: h / 2), radius: h / 2, startAngle: .pi * 3 / 2, endAngle: .pi / 2, clockwise: false)
        context.fillPath()
        
        context.setBlendMode(.xor)
        context.fillEllipse(in: CGRect(x: (checked ? w - h : 0) + Self.strokeWidth, y: Self.strokeWidth, width: h - 2 * Self.strokeWidth, height: h - 2 * Self.strokeWidth))
    }
    func draw(context: CGContext, baseFontSize: CGFloat) {
        context.saveGState()
        context.translateBy(x: pos.x, y: pos.y)
        if landscape { context.rotate(by: .pi / 2) }
        
        let size = baseFontSize * fontSize
        switch style {
        case .checkbox: drawCheckbox(context: context, size: size)
        case .toggleswitch: drawToggleswitch(context: context, size: size)
        }
        
        let textbox = CGRect(x: box.width + Self.textPadding, y: box.height / 2 - size, width: .infinity, height: 2 * size)
        drawString(text, in: textbox, context: context, fontSize: size, align: .left, color: textColor, centerY: true)
        
        context.restoreGState()
    }
    
    func contains(pos: CGPoint) -> Bool {
        if box == .zero { return false }
        let base = CGRect(origin: self.pos, size: box)
        return inflate(rect: landscape ? rotate(rect: base) : base, by: Self.clickPadding).contains(pos)
    }
    func mouseDown(core: CoreController, pos: CGPoint) {
        if !readonly {
            checked.toggle()
            core.send(core.netsbloxify([ UInt8(ascii: "z"), checked ? 1 : 0 ] + id))
        }
    }
    func mouseMove(core: CoreController, pos: CGPoint) { }
    func mouseUp(core: CoreController) { }
    
    func getToggleState() -> Bool {
        checked
    }
    func setToggleState(_ state: Bool) {
        checked = state
    }
    
    func getText() -> String {
        text
    }
    func setText(_ txt: String) {
        text = txt
    }
}
