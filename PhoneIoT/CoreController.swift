//
//  CoreController.swift
//  PhoneIoT
//
//  Created by Devin Jean on 3/24/21.
//

import SwiftUI
import Network
import AVFAudio
import AVFoundation

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

func rotate(rect: CGRect) -> CGRect {
    CGRect(x: rect.origin.x - rect.size.height, y: rect.origin.y, width: rect.size.height, height: rect.size.width)
}
func inflate(rect: CGRect, by padding: CGFloat) -> CGRect {
    CGRect(x: rect.origin.x - padding, y: rect.origin.y - padding, width: rect.width + 2 * padding, height: rect.height + 2 * padding)
}

let IP_REGEX = try! NSRegularExpression(pattern: "^(\\d+\\.){3}\\d+$")
func is_ip(_ addr: String) -> Bool {
    IP_REGEX.firstMatch(in: addr, options: [], range: NSRange(location: 0, length: addr.utf16.count)) != nil
}
func http_get(_ addr: String, then: @escaping (String?) -> ()) {
    print("http get \(addr)")
    guard let url = URL(string: addr) else { return then(nil) }
    
    URLSession.shared.dataTask(with: url) { (data, response, error) in
        guard let data = data else { return then(nil) }
        then(String(bytes: data, encoding: .utf8))
    }.resume()
}

class CoreController: ObservableObject {
    var initialized = false
    var scenePhase: ScenePhase = .background
    
    @Published var showMenu = false
    
    @Published var showImagePicker = false
    var imagePickerTarget: ImageLike?
    
    @Published var showEditText = false
    @Published var editText: String = ""
    var editTextTarget: TextLike?
    
    @Published var changePasswordDialog = false
    @Published var runInBackgroundDialog = false
    
    @Published var runInBackground = false
    
    @Published var macaddr = [UInt8](repeating: 0, count: 6)
    @Published var password: UInt64 = 0
    @Published var passwordExpiry: Double = .infinity
    
    static let passwordLifecycle: Double = 24 * 60 * 60
    
    @Published var addresstxt: String = "10.0.0.24"
    static let defaultServerPort: UInt16 = 1976
    
    @Published var toastMessages = [(String, TimeInterval)]()
    var toastRunning = false
    
    var udp: NWConnection?
    var heatbeatTimer: Timer?
    static let heartbeatInterval: Double = 30
    
    var sensorUpdateTimer: Timer?
    var sensorUpdateCount: UInt32 = 0
    
    var controls = [CustomControl]() // we need to wrap this in a class so we can pas it by reference
    var canvasSize: CGSize = CGSize(width: 50, height: 50)
    static let maxControls: Int = 1024
    
    // checks if we should be live an performing communication with the server
    func isLive() -> Bool {
        return scenePhase == .active || runInBackground
    }
    
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
        guard isLive() else { return }
        
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
    func getSensorPacket(prefix: [UInt8]) -> [UInt8] {
        var res = prefix + toBEBytes(u32: sensorUpdateCount)
        sensorUpdateCount += 1
        
        let sensors = [
            Sensors.accelerometer, Sensors.gravity, Sensors.linearAcceleration, Sensors.gyroscope,
            Sensors.rotationVector, Sensors.gameRotationVector, Sensors.magnetometer,
            Sensors.proximity, Sensors.proximity, Sensors.stepCount, Sensors.light,
            Sensors.location, Sensors.orientation,
        ]
        for sensor in sensors {
            if let data = sensor {
                assert(data.count <= 127)
                res.append(UInt8(data.count))
                for val in data {
                    res.append(contentsOf: toBEBytes(f64: val))
                }
            }
            else {
                res.append(0)
            }
        }
        
        return res
    }
    func setSensorUpdatePeriods(_ periods: [Int]) {
        DispatchQueue.main.async { // timers have to be spawned in a thread with a run loop
            self.sensorUpdateTimer?.invalidate()
            
            if let interval = periods.min() { // interval is in ms - we just match the smallest (finest) value
                self.sensorUpdateTimer = Timer.scheduledTimer(withTimeInterval: Double(interval) / 1000, repeats: true) { t in
                    self.send(self.netsbloxify(self.getSensorPacket(prefix: [ UInt8(ascii: "Q") ])[...]))
                }
            }
            else {
                self.sensorUpdateTimer = nil
            }
        }
    }
    func messageHandler(msg: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) {
        // go ahead and re-register ourselves to receive the next packet
        if let udp = udp {
            switch udp.state {
            case .failed(_):
                if scenePhase == .active { // if not active, networking will be disconnect and it will fail again
                    DispatchQueue.main.async { self.connectToServer() } // we need to do this from main thread because of the timer
                    return
                }
            default: break
            }
            udp.receiveMessage(completion: messageHandler)
        }
        
        // handle the message, if valid
        if msg != nil && error == nil && isComplete {
            let content = [UInt8](msg!)

            // don't do any communication if we're not live (we can receive, but don't respond)
            if !isLive() { return }
            
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
            case UInt8(ascii: "A"): send(heading: content[0], sensorData: Sensors.accelerometer)
            case UInt8(ascii: "G"): send(heading: content[0], sensorData: Sensors.gravity)
            case UInt8(ascii: "L"): send(heading: content[0], sensorData: Sensors.linearAcceleration)
            case UInt8(ascii: "Y"): send(heading: content[0], sensorData: Sensors.gyroscope)
            case UInt8(ascii: "R"): send(heading: content[0], sensorData: Sensors.rotationVector)
            case UInt8(ascii: "r"): send(heading: content[0], sensorData: nil) // game rotation vector
            case UInt8(ascii: "M"): send(heading: content[0], sensorData: Sensors.magnetometer)
            case UInt8(ascii: "m"): send(heading: content[0], sensorData: Sensors.microphone)
            case UInt8(ascii: "P"): send(heading: content[0], sensorData: Sensors.proximity)
            case UInt8(ascii: "S"): send(heading: content[0], sensorData: Sensors.stepCount)
            case UInt8(ascii: "l"): send(heading: content[0], sensorData: nil) // light level
            case UInt8(ascii: "X"): send(heading: content[0], sensorData: Sensors.location)
            case UInt8(ascii: "O"): send(heading: content[0], sensorData: nil) // orientation
                
            // authenticate
            case UInt8(ascii: "a"): send(netsbloxify([ content[0] ]))
            
            // set sensor packet update intervals
            case UInt8(ascii: "p"): if content.count >= 9 && (content.count - 9) % 4 == 0 {
                var vals = [Int]()
                for i in 0..<((content.count - 9) / 4) {
                    vals.append(Int(fromBEBytes(u32: content[(9 + i * 4)..<(9 + (i + 1) * 4)])))
                }
                setSensorUpdatePeriods(vals)
                send(netsbloxify([ content[0] ]))
            }
                
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
                            control.setText(txt)
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
            
            // set image
            case UInt8(ascii: "i"): if content.count >= 10 {
                let idlen = Int(content[9])
                if content.count >= 10 + idlen {
                    if let target = getControl(id: content[10..<10+idlen]) as? ImageLike {
                        if let img = uiImage(jpeg: content[(10+idlen)...]) {
                            if let final = cgImage(uiImage: img) {
                                target.setImage(final)
                                triggerUpdate()
                                send(netsbloxify([ content[0], 0 ]))
                            }
                        }
                    }
                    else {
                        send(netsbloxify([ content[0], 3 ]))
                    }
                }
            }
            
            // get image
            case UInt8(ascii: "u"): if content.count >= 9 {
                if let target = getControl(id: content[9...]) as? ImageLike {
                    if let data = jpeg(uiImage: uiImage(cgImage: target.getImage())) {
                        send(netsbloxify([ content[0] ] + data))
                    }
                }
                else {
                    send(netsbloxify([ content[0] ]))
                }
            }
            
            // set toggle state
            case UInt8(ascii: "w"): if content.count >= 10 {
                let state = content[9] != 0
                if let control = getControl(id: content[10...]) as? ToggleLike {
                    control.setToggleState(state)
                    triggerUpdate()
                    send(netsbloxify([ content[0], 0 ]))
                }
                else {
                    send(netsbloxify([ content[0], 3 ]))
                }
            }
            
            // get toggle state
            case UInt8(ascii: "W"): if content.count >= 9 {
                let control = getControl(id: content[9...]) as? ToggleLike
                send(netsbloxify([ content[0], control == nil ? 2 : control!.getToggleState() ? 1 : 0 ]))
            }
            
            // is pushed
            case UInt8(ascii: "V"): if content.count >= 9 {
                let control = getControl(id: content[9...]) as? PushLike
                send(netsbloxify([ content[0], control == nil ? 2 : control!.isPushed() ? 1 : 0 ]))
            }
            
            // get position
            case UInt8(ascii: "J"): if content.count >= 9 {
                if let control = getControl(id: content[9...]) as? PositionLike {
                    if let pos = control.getPos() {
                        send(netsbloxify([ content[0], 1 ] + toBEBytes(cgf32: pos.x) + toBEBytes(cgf32: pos.y)))
                    }
                    else {
                        send(netsbloxify([ content[0], 0] ))
                    }
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
            
            // add text field
            case UInt8(ascii: "T"): if content.count >= 41 {
                let x = fromBEBytes(cgf32: content[9..<13]) / 100 * canvasSize.width
                let y = fromBEBytes(cgf32: content[13..<17]) / 100 * canvasSize.height
                let width = fromBEBytes(cgf32: content[17..<21]) / 100 * canvasSize.width
                let height = fromBEBytes(cgf32: content[21..<25]) / 100 * canvasSize.height
                let color = fromBEBytes(cgcolor: content[25..<29])
                let textColor = fromBEBytes(cgcolor: content[29..<33])
                let fontSize = fromBEBytes(cgf32: content[33..<37])
                let align = fromBEBytes(align: content[37])
                let readonly = content[38] != 0
                let landscape = content[39] != 0
                let idlen = Int(content[40])
                if content.count >= 41 + idlen {
                    let id = [UInt8](content[41..<(41+idlen)])
                    if let text = String(bytes: content[(41+idlen)...], encoding: .utf8) {
                        let control = CustomTextField(x: x, y: y, width: width, height: height, color: color, textColor: textColor, id: id, text: text, readonly: readonly, fontSize: fontSize, align: align, landscape: landscape)
                        send(netsbloxify([ content[0], tryAddControl(control: control) ]))
                    }
                }
            }
            
            // add image display
            case UInt8(ascii: "U"): if content.count >= 28 {
                let x = fromBEBytes(cgf32: content[9..<13]) / 100 * canvasSize.width
                let y = fromBEBytes(cgf32: content[13..<17]) / 100 * canvasSize.height
                let width = fromBEBytes(cgf32: content[17..<21]) / 100 * canvasSize.width
                let height = fromBEBytes(cgf32: content[21..<25]) / 100 * canvasSize.height
                let readonly = content[25] != 0
                let landscape = content[26] != 0
                let fit = fromBEBytes(imgfit: content[27])
                let id = [UInt8](content[28...])
                
                let control = CustomImageDisplay(x: x, y: y, width: width, height: height, id: id, readonly: readonly, landscape: landscape, fit: fit)
                send(netsbloxify([ content[0], tryAddControl(control: control) ]))
            }
            
            // add joystick
            case UInt8(ascii: "j"): if content.count >= 26 {
                let x = fromBEBytes(cgf32: content[9..<13]) / 100 * canvasSize.width
                let y = fromBEBytes(cgf32: content[13..<17]) / 100 * canvasSize.height
                let radius = fromBEBytes(cgf32: content[17..<21]) / 100 * canvasSize.width
                let color = fromBEBytes(cgcolor: content[21..<25])
                let landscape = content[25] != 0
                let id = [UInt8](content[26...])
                
                let control = CustomJoystick(x: x, y: y, r: radius, color: color, id: id, landscape: landscape)
                send(netsbloxify([ content[0], tryAddControl(control: control) ]))
            }
            
            // add touchpad
            case UInt8(ascii: "N"): if content.count >= 31 {
                let x = fromBEBytes(cgf32: content[9..<13]) / 100 * canvasSize.width
                let y = fromBEBytes(cgf32: content[13..<17]) / 100 * canvasSize.height
                let width = fromBEBytes(cgf32: content[17..<21]) / 100 * canvasSize.width
                var height = fromBEBytes(cgf32: content[21..<25]) / 100 * canvasSize.height
                let color = fromBEBytes(cgcolor: content[25..<29])
                if content[29] == 1 {
                    height = width
                }
                let landscape = content[30] != 0
                let id = [UInt8](content[31...])
                
                let control = CustomTouchpad(x: x, y: y, width: width, height: height, color: color, id: id, landscape: landscape)
                send(netsbloxify([ content[0], tryAddControl(control: control) ]))
            }
            
            // add toggle
            case UInt8(ascii: "Z"): if content.count >= 34 {
                let x = fromBEBytes(cgf32: content[9..<13]) / 100 * canvasSize.width
                let y = fromBEBytes(cgf32: content[13..<17]) / 100 * canvasSize.height
                let checkColor = fromBEBytes(cgcolor: content[17..<21])
                let textColor = fromBEBytes(cgcolor: content[21..<25])
                let fontSize = fromBEBytes(cgf32: content[25..<29])
                let checked = content[29] != 0
                let style = fromBEBytes(togglestyle: content[30])
                let landscape = content[31] != 0
                let readonly = content[32] != 0
                let idlen = Int(content[33])
                if content.count >= 34 + idlen {
                    let id = [UInt8](content[34..<(34+idlen)])
                    if let text = String(bytes: content[(34+idlen)...], encoding: .utf8) {
                        let control = CustomToggle(x: x, y: y, checkColor: checkColor, textColor: textColor, checked: checked, id: id, text: text, style: style, fontSize: fontSize, landscape: landscape, readonly: readonly)
                        send(netsbloxify([ content[0], tryAddControl(control: control) ]))
                    }
                }
            }
            
            // add radio button
            case UInt8(ascii: "y"): if content.count >= 33 {
                let x = fromBEBytes(cgf32: content[9..<13]) / 100 * canvasSize.width
                let y = fromBEBytes(cgf32: content[13..<17]) / 100 * canvasSize.height
                let checkColor = fromBEBytes(cgcolor: content[17..<21])
                let textColor = fromBEBytes(cgcolor: content[21..<25])
                let fontSize = fromBEBytes(cgf32: content[25..<29])
                let checked = content[29] != 0
                let landscape = content[30] != 0
                let readonly = content[31] != 0
                let idlen = Int(content[32])
                if content.count >= 33 + idlen + 1 {
                    let id = [UInt8](content[33..<(33+idlen)])
                    let grouplen = Int(content[33+idlen])
                    if content.count >= 33 + idlen + 1 + grouplen {
                        let group = [UInt8](content[(33 + idlen + 1)..<(33 + idlen + 1 + grouplen)])
                        if let text = String(bytes: content[(33 + idlen + 1 + grouplen)...], encoding: .utf8) {
                            let control = CustomRadiobutton(x: x, y: y, checkColor: checkColor, textColor: textColor, checked: checked, id: id, group: group, text: text, fontSize: fontSize, landscape: landscape, readonly: readonly)
                            send(netsbloxify([ content[0], tryAddControl(control: control) ]))
                        }
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
        
        let addr = addresstxt // captured for the closure
        let target = is_ip(addr) ? addr + ":8080" : addr.starts(with: "https://") ? addr : "https://" + addr
        http_get(target + "/services/routes/phone-iot/port") { content in
            let port = UInt16(content ?? "") ?? Self.defaultServerPort
            
            // start up the connection
            print("connecting to \(addr):\(port)")
            self.udp = NWConnection(
                host: NWEndpoint.Host(addr),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .udp)
            self.udp!.start(queue: .global())
            
            // start listening for (complete) packets
            self.udp!.receiveMessage(completion: self.messageHandler)
            
            // start the hearbeat timer if it isn't already - we need one per 2 min, so 30 secs will allow for some dropped packets
            if self.heatbeatTimer == nil {
                self.heatbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { t in
                    self.send(self.netsbloxify([ UInt8(ascii: "I") ]))
                }
            }
            
            // send a heartbeat to connect immediately, but add a conn ack request flag so we get a message back
            self.send(self.netsbloxify([ UInt8(ascii: "I"), 0 ]))
        }
    }
    
    func initialize() {
        if initialized { return }
        scenePhase = .active // we don't get updates for the first scene phase, so we're doing this from onAppear on the main app view
        
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
        
        // read the stored "runinbackground" for the device
        runInBackground = defaults.bool(forKey: "runinbackground") // default if not defined is false, which works for our needs
        
        Sensors.start()
        
        // set raw textview backgrounds to transparent so we can modify the background colors of their wrappers
        UITextView.appearance().backgroundColor = .clear
        
        initialized = true
    }
}
