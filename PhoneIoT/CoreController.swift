//
//  CoreController.swift
//  PhoneIoT
//
//  Created by Devin Jean on 3/24/21.
//

import SwiftUI
import Network

func toHex(bytes: ArraySlice<UInt8>) -> String {
    bytes.map({ String(format: "%02x", $0) }).joined()
}
func getTime() -> Double {
    NSTimeIntervalSince1970
}

func ellipseContains(ellipse: CGRect, point: CGPoint) -> Bool {
    let rx = ellipse.width / 2
    let ry = ellipse.height / 2
    let offx = point.x - (ellipse.minX + rx)
    let offy = point.y - (ellipse.minY + ry)
    return (offx * offx) / (rx * rx) + (offy * offy) / (ry * ry) <= 1
}

func defaultImage(color: CGColor?) -> UIImage {
    UIGraphicsBeginImageContext(CGSize(width: 50, height: 50))
    
    if let color = color {
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(color)
        context.fill(.infinite)
    }
    
    let img = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return img
}

class CoreController: ObservableObject {
    @Published var showMenu = false
    
    @Published var changePasswordDialog = false
    @Published var runInBackgroundDialog = false
    
    @Published var runInBackground = false
    
    @Published var macaddr = [UInt8](repeating: 0, count: 6)
    @Published var password: UInt64 = 0
    @Published var passwordExpiry: Double = Double.infinity
    
    static let passwordLifecycle: Double = 24 * 60 * 60
    
    @Published var addresstxt: String = "10.0.0.24"
    static let serverPort: UInt16 = 1976
    
    @Published var toastMessages = [(String, TimeInterval)]()
    var toastRunning = false
    
    var udp: NWConnection?
    var heatbeatTimer: Timer?
    static let heartbeatInterval: Double = 30
    
    var controls = [CustomControl]() // we need to wrap this in a class so we can pas it by reference
    var canvasSize: CGSize = CGSize(width: 50, height: 50)
    static let maxControls: Int = 1024
    
    @Published var updateTrigger = false // value doesn't matter, we just toggle it to invalidate the view
    func triggerUpdate() {
        DispatchQueue.main.async {
            self.updateTrigger.toggle() // publish actions must execute on main thread
        }
    }
    
    func render(size: CGSize) -> UIImage {
        canvasSize = size // keep track of the size of the canvas for other things to use
        
        // if the image would be empty it'll crash - avoid that by giving a default image
        if size.width == 0 || size.height == 0 {
            return defaultImage(color: nil)
        }
        UIGraphicsBeginImageContext(size)
        
        let baseFontSize = 30 * size.height / 1200
        let context = UIGraphicsGetCurrentContext()!
        for control in controls {
            control.draw(context: context, baseFontSize: baseFontSize)
        }
        if controls.isEmpty {
            let str = NSAttributedString(string: "Add controls through NetsBlox!", attributes: [.font: UIFont.systemFont(ofSize: baseFontSize)])
            let bound = str.boundingRect(with: CGSize(width: CGFloat.infinity, height: .infinity), options: .usesLineFragmentOrigin, context: nil)
            let pos = CGPoint(x: (size.width - bound.size.width) / 2, y: (size.height - bound.size.height) / 2)
            
            UIGraphicsPushContext(context)
            str.draw(with: CGRect(origin: pos, size: bound.size), options: .usesLineFragmentOrigin, context: nil)
            UIGraphicsPopContext()
        }
        
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }
    func tryAddControl(control: CustomControl) -> UInt8 {
        if controls.count >= Self.maxControls { return 1 }
        let id = control.getID()
        for other in controls {
            if other.getID() == id { return 2 }
        }
        controls.append(control)
        triggerUpdate()
        return 0
    }
    func removeControl(id: ArraySlice<UInt8>) {
        for (i, control) in controls.enumerated() {
            if control.getID() == id {
                controls.remove(at: i)
                triggerUpdate()
                break
            }
        }
    }
    func removeAllControls() {
        controls.removeAll()
        triggerUpdate()
    }
    func getControl(at pos: CGPoint) -> CustomControl? {
        for control in controls.reversed() {
            if control.contains(pos: pos) {
                return control
            }
        }
        return nil
    }
    func getControl(id: ArraySlice<UInt8>) -> CustomControl? {
        for control in controls {
            if control.getID() == id {
                return control
            }
        }
        return nil
    }
    
    private func _startToast() {
        assert(!toastRunning && !toastMessages.isEmpty)
        toastRunning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + toastMessages.first!.1) {
            self.toastRunning = false
            self.toastMessages.remove(at: 0)
            if !self.toastMessages.isEmpty {
                self._startToast() // handle any others we might have
            }
        }
    }
    private func toast(msg: String, duration: TimeInterval) {
        DispatchQueue.main.async { // done in the same dispatch queue because it's a critical section
            self.toastMessages.append((msg, duration))
            if !self.toastRunning {
                self._startToast()
            }
        }
    }
    
    func getPassword() -> UInt64 {
        let time = getTime()
        if time < passwordExpiry {
            return password
        }
        
        password = UInt64.random(in: 0...0xffffffff)
        passwordExpiry = time + Self.passwordLifecycle
        print("changed password to \(password)")
        return password
    }
    func netsbloxify(_ msg: ArraySlice<UInt8>) -> [UInt8] {
        var expanded = [UInt8]()
        expanded.append(contentsOf: macaddr)
        expanded.append(contentsOf: [0, 0, 0, 0])
        expanded.append(contentsOf: msg)
        return expanded
    }
    func send(_ msg: [UInt8]) {
        udp?.send(content: msg, completion: .contentProcessed { err in
            if let err = err {
                print("send error: \(err)")
            }
        })
    }
    func send(heading: UInt8, sensorData: [Double]?) {
        var msg = [UInt8]()
        msg.append(heading)
        for datum in sensorData ?? [] {
            msg.append(contentsOf: toBEBytes(u64: datum.bitPattern))
        }
        send(netsbloxify(msg[...]))
    }
    func messageHandler(msg: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) {
        // go ahead and re-register ourselves to receive the next packet
        udp?.receiveMessage(completion: messageHandler)
        
        // handle the message, if valid
        if msg != nil && error == nil && isComplete {
            let content = [UInt8](msg!)

            // check for things that don't need auth
            if content.count == 1 && content[0] == UInt8(ascii: "I") {
                // connected to server ack - give user a message
                toast(msg: "Connected to NetsBlox", duration: 3)
                return
            }

            // ignore anything that's invalid or fails to auth
            if content.count < 9 || fromBEBytes(u64: content[1..<9]) != getPassword() {
                return
            }

            switch content[0] {
            case UInt8(ascii: "A"): send(heading: content[0], sensorData: Sensors.accelerometer.getData())
                
            // authenticate
            case UInt8(ascii: "a"): send(netsbloxify([ content[0] ]))
            
            // clear controls
            case UInt8(ascii: "C"): if content.count == 9 {
                removeAllControls()
                send(netsbloxify([ content[0] ]))
            }
            
            // remove control
            case UInt8(ascii: "c"): if content.count >= 9 {
                let id = content[9...]
                for (i, control) in controls.enumerated() {
                    if control.getID() == id {
                        controls.remove(at: i)
                        triggerUpdate()
                        break
                    }
                }
                send(netsbloxify([ content[0] ]))
            }
            
            // set text
            case UInt8(ascii: "H"): if content.count >= 10 {
                let idlen = Int(content[9])
                if content.count >= 10 + idlen {
                    if let control = getControl(id: content[10..<10+idlen]) as? TextLike {
                        if let txt = String(bytes: content[(10+idlen)...], encoding: .utf8) {
                            control.setText(txt: txt)
                            triggerUpdate()
                            send(netsbloxify([ content[0], 0 ]))
                        }
                    }
                    else {
                        send(netsbloxify([ content[0], 3 ]))
                    }
                }
            }
            
            // get text
            case UInt8(ascii: "h"): if content.count >= 9 {
                if let control = getControl(id: content[9...]) as? TextLike {
                    send(netsbloxify([ content[0], 0 ] + control.getText().utf8))
                }
                else {
                    send(netsbloxify([ content[0] ]))
                }
            }
            
            // add label
            case UInt8(ascii: "g"): if content.count >= 28 {
                let x = fromBEBytes(cgf32: content[9..<13]) / 100 * canvasSize.width
                let y = fromBEBytes(cgf32: content[13..<17]) / 100 * canvasSize.height
                let textColor = fromBEBytes(cgcolor: content[17..<21])
                let fontSize = fromBEBytes(cgf32: content[21..<25])
                let align = fromBEBytes(align: content[25])
                let landscape = content[26] != 0
                let idlen = Int(content[27])
                if content.count >= 28 + idlen {
                    let id = [UInt8](content[28..<28+idlen])
                    if let text = String(bytes: content[(28+idlen)...], encoding: .utf8) {
                        let control = CustomLabel(x: x, y: y, textColor: textColor, id: id, text: text, fontSize: fontSize, align: align, landscape: landscape)
                        send(netsbloxify([ content[0], tryAddControl(control: control) ]))
                    }
                }
            }
            
            // add button
            case UInt8(ascii: "B"): if content.count >= 40 {
                let x = fromBEBytes(cgf32: content[9..<13]) / 100 * canvasSize.width
                let y = fromBEBytes(cgf32: content[13..<17]) / 100 * canvasSize.height
                let width = fromBEBytes(cgf32: content[17..<21]) / 100 * canvasSize.width
                var height = fromBEBytes(cgf32: content[21..<25]) / 100 * canvasSize.height
                let color = fromBEBytes(cgcolor: content[25..<29])
                let textColor = fromBEBytes(cgcolor: content[29..<33])
                let fontSize = fromBEBytes(cgf32: content[33..<37])
                var style: ButtonStyle
                switch content[37] {
                case 0: style = .Rectangle
                case 1: style = .Ellipse
                case 2: height = width; style = .Rectangle
                case 3: height = width; style = .Ellipse
                default: style = .Rectangle
                }
                let landscape = content[38] != 0
                let idlen = Int(content[39])
                if content.count >= 40 + idlen {
                    let id = [UInt8](content[40..<40+idlen])
                    if let text = String(bytes: content[(40+idlen)...], encoding: .utf8) {
                        let control = CustomButton(x: x, y: y, width: width, height: height, color: color, textColor: textColor, id: id, text: text, fontSize: fontSize, style: style, landscape: landscape)
                        send(netsbloxify([ content[0], tryAddControl(control: control) ]))
                    }
                }
            }
            
            default: print("unrecognized request code: \(content[0])")
            }
        }
    }
    func connectToServer() {
        // if we already had a connection, kill it first
        if let old = udp {
            print("killing previous connection")
            old.cancel()
        }
        
        // start up the connection
        print("connecting to \(addresstxt):\(Self.serverPort)")
        udp = NWConnection(
            host: NWEndpoint.Host(addresstxt),
            port: NWEndpoint.Port(rawValue: Self.serverPort)!,
            using: .udp)
        udp!.start(queue: .global())
        
        // start listening for (complete) packets
        udp?.receiveMessage(completion: messageHandler)
        
        // start the hearbeat timer if it isn't already - we need one per 2 min, so 30 secs will allow for some dropped packets
        if heatbeatTimer == nil {
            heatbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { t in
                self.send(self.netsbloxify([ UInt8(ascii: "I") ]))
            }
        }
        
        // send a heartbeat to connect immediately, but add a conn ack request flag so we get a message back
        send(netsbloxify([ UInt8(ascii: "I"), 0 ]))
    }
    
    func initialize() {
        // read the stored "macaddr" for the device, or generate a new persistent one if none exists
        let defaults = UserDefaults.standard
        var addr = defaults.array(forKey: "macaddr") as? [UInt8]
        if addr == nil {
            var res = [UInt8]()
            for _ in 0..<6 {
                res.append(UInt8.random(in: UInt8.min...UInt8.max))
            }
            defaults.set(res, forKey: "macaddr")
            addr = res
        }
        macaddr = addr!
        
        // start up all the sensors
        Sensors.start()
    }
}
