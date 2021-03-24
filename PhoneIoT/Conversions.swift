//
//  Conversions.swift
//  PhoneIoT
//
//  Created by Devin Jean on 3/22/21.
//

import Foundation
import SwiftUI

func fromBEBytes(u64: ArraySlice<UInt8>) -> UInt64 {
    assert(u64.count == 8)
    let data = Data(u64)
    return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
}
func toBEBytes(u64: UInt64) -> [UInt8] {
    withUnsafeBytes(of: u64.bigEndian, Array.init)
}

func fromBEBytes(u32: ArraySlice<UInt8>) -> UInt32 {
    assert(u32.count == 4)
    let data = Data(u32)
    return UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
}
func toBEBytes(u32: UInt32) -> [UInt8] {
    withUnsafeBytes(of: u32.bigEndian, Array.init)
}

func fromBEBytes(f64: ArraySlice<UInt8>) -> Double {
    Double(bitPattern: fromBEBytes(u64: f64))
}
func toBEBytes(f64: Double) -> [UInt8] {
    toBEBytes(u64: f64.bitPattern)
}

func fromBEBytes(f32: ArraySlice<UInt8>) -> Float {
    Float(bitPattern: fromBEBytes(u32: f32))
}
func toBEBytes(f32: Float) -> [UInt8] {
    toBEBytes(u32: f32.bitPattern)
}
func fromBEBytes(cgf32: ArraySlice<UInt8>) -> CGFloat {
    CGFloat(fromBEBytes(f32: cgf32))
}
func toBEBytes(cgf32: CGFloat) -> [UInt8] {
    toBEBytes(f32: Float(cgf32))
}

func fromBEBytes(cgcolor: ArraySlice<UInt8>) -> CGColor {
    let raw = fromBEBytes(u32: cgcolor)
    return CGColor(
        red: CGFloat((raw >> 16) & 0xff) / 255,
        green: CGFloat((raw >> 8) & 0xff) / 255,
        blue: CGFloat(raw & 0xff) / 255,
        alpha: CGFloat(raw >> 24) / 255)
}
func fromBEBytes(align: UInt8) -> NSTextAlignment {
    switch align {
    case 1: return .center
    case 2: return .right
    default: return .left
    }
}
