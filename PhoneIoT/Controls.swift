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
    func getImage() -> UIImage
    func setImage(img: UIImage)
}
protocol TextLike: CustomControl {
    func getText() -> String
    func setText(txt: String)
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
        
        context.setTextDrawingMode(.fill)
        context.setFontSize(baseFontSize * fontSize)
        let font = UIFont.systemFont(ofSize: baseFontSize * fontSize)
        let par = NSMutableParagraphStyle()
        par.alignment = .center
        par.lineBreakMode = .byWordWrapping
        let str = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: par, .strokeColor: textColor, .foregroundColor: textColor])
        let bound = str.boundingRect(with: textRect.size, options: .usesLineFragmentOrigin, context: nil)
        let pos = CGPoint(x: textRect.origin.x, y: textRect.origin.y + (textRect.size.height - bound.size.height) / 2)
        
        UIGraphicsPushContext(context)
        str.draw(with: CGRect(origin: pos, size: textRect.size), options: .usesLineFragmentOrigin, context: nil)
        UIGraphicsPopContext()
        
        if pressed {
            context.setFillColor(Self.pressColor)
            fillRegion(context: context, rect: mainRect)
        }
        
        context.restoreGState()
    }
    
    func contains(pos: CGPoint) -> Bool {
        switch style {
        case .Rectangle: return rect.contains(pos)
        case .Ellipse: return ellipseContains(ellipse: landscape ? CGRect(x: rect.origin.x - rect.size.height, y: rect.origin.y, width: rect.size.height, height: rect.size.width) : rect, point: pos)
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
    func setText(txt: String) {
        text = txt
    }
}
