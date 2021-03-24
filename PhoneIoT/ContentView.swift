//
//  ContentView.swift
//  PhoneIoT
//
//  Created by Devin Jean on 2/25/21.
//

import SwiftUI
import Network

func toHex(bytes: ArraySlice<UInt8>) -> String {
    bytes.map({ String(format: "%02x", $0) }).joined()
}
func getTime() -> Double {
    NSTimeIntervalSince1970
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

class TouchData {
    var lastPos: CGPoint
    var control: CustomControl
    
    init(pos: CGPoint, control: CustomControl) {
        self.lastPos = pos
        self.control = control
    }
}
class TouchTracker: UIView {
    var activeTouches = [UITouch : TouchData]()
    var core: CoreController?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        isMultipleTouchEnabled = true
    }

    func isTouchTarget(control: CustomControl) -> Bool {
        for (_, data) in activeTouches {
            if data.control === control {
                return true
            }
        }
        return false
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var didSomething = false
        
        for touch in touches {
            let pos = touch.location(in: self)
            //print("\(activeTouches.count) touch start \(pos)")
            if let control = core?.getControl(at: pos) {
                if !isTouchTarget(control: control) { // don't allow multiple touches on same control
                    activeTouches[touch] = TouchData(pos: pos, control: control)
                    control.mouseDown(core: core!, pos: pos)
                    didSomething = true
                }
            }
        }
        
        if didSomething { core?.triggerUpdate() }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var didSomething = false
        
        for touch in touches {
            let pos = touch.location(in: self)
            //print("\(activeTouches.count) touch move \(pos)")
            if let data = activeTouches[touch] {
                if data.lastPos != pos {
                    data.lastPos = pos
                    data.control.mouseMove(core: core!, pos: pos)
                    didSomething = true
                }
            }
        }
        
        if didSomething { core?.triggerUpdate() }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        var didSomething = false
        
        for touch in touches {
            //print("\(activeTouches.count) touch end")
            if let data = activeTouches.removeValue(forKey: touch) {
                data.control.mouseUp(core: core!)
                didSomething = true
            }
        }
        
        if didSomething { core?.triggerUpdate() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
struct TouchTrackerView: UIViewRepresentable {
    @State private var core: CoreController
    
    func makeUIView(context: Context) -> TouchTracker {
        let t = TouchTracker()
        t.core = core
        return t
    }
    func updateUIView(_ uiView: TouchTracker, context: Context) { }
    
    init(core: CoreController) {
        self.core = core
    }
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
            case UInt8(ascii: "a"): send(netsbloxify([ content[0] ]))
            
            // clear controls
            case UInt8(ascii: "C"): if content.count == 9 {
                removeAllControls()
                send(netsbloxify([ content[0] ]))
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
                let id = [UInt8](content[40..<40+idlen])
                if let text = String(bytes: content[(40+idlen)...], encoding: .utf8) {
                    let control = CustomButton(x: x, y: y, width: width, height: height, color: color, textColor: textColor, id: id, text: text, fontSize: fontSize, style: style, landscape: landscape)
                    send(netsbloxify([ content[0], tryAddControl(control: control) ]))
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
}

struct ContentView: View {
    @StateObject var core = CoreController()
    
    private func initialize() {
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
        core.macaddr = addr!
        
        // start up all the sensors
        Sensors.start()
    }
    var body: some View {
        NavigationView {
            ZStack {
                GeometryReader { geometry in
                    Image(uiImage: core.render(size: geometry.size))
                        .resizable()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                TouchTrackerView(core: core) // needs to be in front of the canvas to get touch events
                GeometryReader { geometry in
                    let menuWidth = min(max(geometry.size.width * 0.5, 350), geometry.size.width * 0.9)
                    
                    HStack {
                        VStack {
                            Group {
                                Spacer().frame(height: 20)
                                
                                Image("AppIcon-180")
                                    .resizable()
                                    .frame(width: menuWidth / 4, height: menuWidth / 4)
                                
                                Text("PhoneIoT")
                                    .font(.system(size: 24))
                                
                                Spacer().frame(height: 5)
                                
                                Text("Device ID: \(toHex(bytes: core.macaddr[...]))")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color.gray)
                                Text("Password: \(String(format: "%08llx", core.password))")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color.gray)
                                
                                Spacer().frame(height: 40)
                            }
                            Group {
                                Text("Server Address:")
                                
                                TextField("Server Address", text: $core.addresstxt)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 10)
                                Divider().frame(width: menuWidth * 0.9)
                                Spacer().frame(height: 20)
                                
                                Button("Connect") {
                                    core.connectToServer()
                                }
                                .padding(EdgeInsets(top: 7, leading: 15, bottom: 7, trailing: 15))
                                .background(Color.blue)
                                .cornerRadius(5)
                                .foregroundColor(Color.white)
                                
                                Spacer().frame(height: 40)
                                Group {
                                    Toggle("Run In background", isOn: $core.runInBackground)
                                        .onChange(of: core.runInBackground, perform: { _ in
                                            if core.runInBackground {
                                                core.runInBackgroundDialog = true
                                            }
                                        })
                                        .alert(isPresented: $core.runInBackgroundDialog) {
                                            Alert(
                                                title: Text("Warning"),
                                                message: Text("Due to accessing sensor data, running in the background can consume a lot of power if you forget to close the app. Additionally, if location is enabled, it may still be tracked while running in the background."),
                                                primaryButton: .default(Text("OK")) { },
                                                secondaryButton: .cancel(Text("Cancel")) {
                                                    core.runInBackground = false
                                                })
                                        }
                                }
                                .frame(width: menuWidth * 0.7)
                                Spacer().frame(height: 40)
                                
                                Button("New Password") {
                                    core.changePasswordDialog = true
                                }
                                .padding(EdgeInsets(top: 7, leading: 15, bottom: 7, trailing: 15))
                                .background(Color.blue)
                                .cornerRadius(5)
                                .foregroundColor(Color.white)
                                .alert(isPresented: $core.changePasswordDialog) {
                                    Alert(
                                        title: Text("New Password"),
                                        message: Text("Are you sure you would like to generate a new password? This may break active connections."),
                                        primaryButton: .default(Text("OK")) {
                                            core.passwordExpiry = 0
                                            let _ = core.getPassword()
                                        },
                                        secondaryButton: .cancel(Text("Cancel")) { })
                                }
                            }
                            Spacer()
                        }
                        .frame(width: menuWidth, height: geometry.size.height)
                        .background(Color.white.edgesIgnoringSafeArea(.bottom))
                        .offset(x: core.showMenu ? 0 : -UIScreen.main.bounds.width)
                        .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.6))
                        
                        Spacer()
                    }
                    .background(Color.black.opacity(core.showMenu ? 0.5 : 0).edgesIgnoringSafeArea(.bottom))
                }
                GeometryReader { geometry in // this needs to be on top of everything
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            Text(core.toastMessages.first?.0 ?? "")
                                .padding(EdgeInsets(top: 8, leading: 15, bottom: 8, trailing: 15))
                                .background(Color(white: 0.15, opacity: 0.7))
                                .cornerRadius(10)
                                .foregroundColor(Color.white)
                                .offset(y: core.toastMessages.isEmpty ? UIScreen.main.bounds.height : 0)
                                .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.6))
                            Spacer().frame(height: geometry.size.height * 0.05)
                        }
                        Spacer()
                    }
                }
            }.navigationBarTitle("PhoneIoT", displayMode: .inline)
            .navigationBarItems(leading:
                Button(action: {
                    core.showMenu.toggle()
                }, label: {
                    if core.showMenu {
                        Image(systemName: "arrow.left").font(.body).foregroundColor(.black)
                    }
                    else {
                        Image("Menu").renderingMode(.original)
                    }
                })
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: initialize)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
