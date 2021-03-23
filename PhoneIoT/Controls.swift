//
//  Controls.swift
//  PhoneIoT
//
//  Created by Devin Jean on 3/22/21.
//

import SwiftUI

protocol CustomControl {
    func getID() -> ArraySlice<UInt8>
    func draw(context: CGContext, baseFontSize: CGFloat)
}

enum ButtonStyle {
    case Rectangle
    case Ellipse
}
class CustomButton: CustomControl {
    private var rect: CGRect
    private var color: CGColor
    private var textColor: CGColor
    private var id: [UInt8]
    private var text: String
    private var fontSize: CGFloat
    private var style: ButtonStyle
    private var landscape: Bool
    
    private static let padding: CGFloat = 5
    
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
    
    func getID() -> ArraySlice<UInt8> { self.id[...] }
    func draw(context: CGContext, baseFontSize: CGFloat) {
        context.setFillColor(color)
        context.fill(rect)
        let textRect = CGRect(
            origin: CGPoint(x: rect.origin.x + Self.padding, y: rect.origin.y + Self.padding),
            size: CGSize(width: rect.size.width - 2 * Self.padding, height: rect.size.height - 2 * Self.padding))
        
        context.setTextDrawingMode(.fill)
        context.setFillColor(textColor)
        context.setFontSize(baseFontSize * fontSize)
        let font = UIFont.systemFont(ofSize: baseFontSize * fontSize)
        let par = NSMutableParagraphStyle()
        par.alignment = .center
        par.lineBreakMode = .byWordWrapping
        let str = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: par])
        let bound = str.boundingRect(with: textRect.size, options: .usesLineFragmentOrigin, context: nil)
        let pos = CGPoint(x: textRect.origin.x, y: textRect.origin.y + (textRect.size.height - bound.size.height) / 2)
        
        UIGraphicsPushContext(context)
        str.draw(with: CGRect(origin: pos, size: textRect.size), options: .usesLineFragmentOrigin, context: nil)
        UIGraphicsPopContext()
    }
}