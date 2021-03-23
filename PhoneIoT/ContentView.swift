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
func defaultImage(gray: CGFloat) -> UIImage {
    let size = CGSize(width: 50, height: 50)
    UIGraphicsBeginImageContext(size)
    
    let context = UIGraphicsGetCurrentContext()!
    context.setFillColor(gray: gray, alpha: 1.0)
    context.fill(.infinite)
    
    let img = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return img
}
func getTime() -> Double {
    NSTimeIntervalSince1970
}

func fromBEBytes(u64: ArraySlice<UInt8>) -> UInt64 {
    assert(u64.count == 8)
    let data = Data(u64)
    return UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) })
}
func toBEBytes(u64: UInt64) -> [UInt8] {
    withUnsafeBytes(of: u64.bigEndian, Array.init)
}

struct ContentView: View {
    @State private var showMenu = false
    
    @State private var macaddr: [UInt8] = [UInt8](repeating: 0, count: 6)
    @State private var password: UInt64 = 0
    @State private var passwordExpiry: Double = Double.infinity
    private static let passwordLifecycle: Double = 24 * 60 * 60
    
    @State private var controlsImage: UIImage = defaultImage(gray: 1.0)
    
    @State private var addresstxt: String = "10.0.0.24"
    private static let serverPort: UInt16 = 1976
    
    @State private var udp: NWConnection?
    @State private var hearbeatTimer: Timer?
    private static let heartbeatInterval: Double = 30
    
    @State private var changePasswordDialog = false
    @State private var runInBackgroundDialog = false
    
    @State private var runInBackground = false
    
    private func getPassword() -> UInt64 {
        let time = getTime()
        if time < passwordExpiry {
            return password
        }
        
        password = UInt64.random(in: 0...0xffffffff)
        passwordExpiry = time + Self.passwordLifecycle
        print("changed password to \(password)")
        return password
    }
    
    private func netsbloxify(_ msg: ArraySlice<UInt8>) -> [UInt8] {
        var expanded = [UInt8]()
        expanded.append(contentsOf: macaddr)
        expanded.append(contentsOf: [0, 0, 0, 0])
        expanded.append(contentsOf: msg)
        return expanded
    }
    private func send(_ msg: [UInt8]) {
        udp?.send(content: msg, completion: .contentProcessed { err in
            if let err = err {
                print("send error: \(err)")
            }
        })
    }
    private func send(heading: UInt8, sensorData: [Double]?) {
        var msg = [UInt8]()
        msg.append(heading)
        for datum in sensorData ?? [Double]() {
            msg.append(contentsOf: toBEBytes(u64: datum.bitPattern))
        }
        send(netsbloxify(msg[...]))
    }
    private func messageHandler(msg: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) {
        // go ahead and re-register ourselves to receive the next packet
        udp?.receiveMessage(completion: messageHandler)
        
        // handle the message, if valid
        if msg != nil && error == nil && isComplete {
            let content = [UInt8](msg!)

            // check for things that don't need auth
            if content.count == 1 && content[0] == UInt8(ascii: "I") {
                // connected to server ack
                print("connection ack from NetsBlox")
                return
            }

            // ignore anything that's invalid or fails to auth
            if content.count < 9 || fromBEBytes(u64: content[1..<9]) != getPassword() {
                return
            }

            switch content[0] {
            case UInt8(ascii: "A"): send(heading: content[0], sensorData: Sensors.accelerometer.getData())
            case UInt8(ascii: "a"): send(netsbloxify([ content[0] ]))
            default: print("unrecognized request code: \(content[0])")
            }
        }
    }
    private func connectToServer() {
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
        if hearbeatTimer == nil {
            hearbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { t in
                send(netsbloxify([ UInt8(ascii: "I") ]))
            }
        }
        
        // send a heartbeat to connect immediately, but add a conn ack request flag so we get a message back
        send(netsbloxify([ UInt8(ascii: "I"), 0 ]))
    }
    
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
        macaddr = addr!
        
        // start up the sensors
        Sensors.start()
    }
    var body: some View {
        NavigationView {
            ZStack {
                Image(uiImage: controlsImage)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { e in
                                print("click move \(e.location)")
                            }
                            .onEnded { e in
                                print("click end \(e.location)")
                            }
                    )
                
                GeometryReader { geometry in
                    HStack {
                        VStack {
                            Group {
                                Spacer().frame(height: 20)
                                
                                Image("AppIcon-180")
                                    .resizable()
                                    .frame(width: geometry.size.width / 5, height: geometry.size.width / 5)
                                
                                Text("PhoneIoT")
                                    .font(.system(size: 24))
                                
                                Spacer().frame(height: 5)
                                
                                Text("Device ID: \(toHex(bytes: macaddr[...]))")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color.gray)
                                Text("Password: \(String(format: "%08llx", password))")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color.gray)
                                
                                Spacer().frame(height: 40)
                            }
                            Group {
                                Text("Server Address:")
                                
                                TextField("Server Address", text: $addresstxt)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 10)
                                Divider().frame(width: geometry.size.width * 0.7)
                                Spacer().frame(height: 20)
                                
                                Button("Connect") {
                                    connectToServer()
                                }
                                .padding(EdgeInsets(top: 7, leading: 15, bottom: 7, trailing: 15))
                                .background(Color.blue)
                                .cornerRadius(5)
                                .foregroundColor(Color.white)
                                
                                Spacer().frame(height: 40)
                                Group {
                                    Toggle("Run In background", isOn: $runInBackground)
                                        .onChange(of: runInBackground, perform: { _ in
                                            if runInBackground {
                                                runInBackgroundDialog = true
                                            }
                                        })
                                        .alert(isPresented: $runInBackgroundDialog) {
                                            Alert(
                                                title: Text("Warning"),
                                                message: Text("Due to accessing sensor data, running in the background can consume a lot of power if you forget to close the app. Additionally, if location is enabled, it may still be tracked while running in the background."),
                                                primaryButton: .default(Text("OK")) { },
                                                secondaryButton: .cancel(Text("Cancel")) {
                                                    runInBackground = false
                                                })
                                        }
                                }
                                .frame(width: geometry.size.width * 0.6)
                                Spacer().frame(height: 40)
                                
                                Button("New Password") {
                                    changePasswordDialog = true
                                }
                                .padding(EdgeInsets(top: 7, leading: 15, bottom: 7, trailing: 15))
                                .background(Color.blue)
                                .cornerRadius(5)
                                .foregroundColor(Color.white)
                                .alert(isPresented: $changePasswordDialog) {
                                    Alert(
                                        title: Text("New Password"),
                                        message: Text("Are you sure you would like to generate a new password? This may break active connections."),
                                        primaryButton: .default(Text("OK")) {
                                            passwordExpiry = 0
                                            let _ = getPassword()
                                        },
                                        secondaryButton: .cancel(Text("Cancel")) { })
                                }
                            }
                            Spacer()
                        }
                        .frame(width: geometry.size.width * 0.75, height: geometry.size.height)
                        .background(Color.white.edgesIgnoringSafeArea(.bottom))
                        .offset(x: self.showMenu ? 0 : -UIScreen.main.bounds.width)
                        .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.6))
                        
                        Spacer()
                    }
                    .background(Color.black.opacity(self.showMenu ? 0.5 : 0).edgesIgnoringSafeArea(.bottom))
                }
            }.navigationBarTitle("PhoneIoT", displayMode: .inline)
            .navigationBarItems(leading:
                Button(action: {
                    showMenu.toggle()
                }, label: {
                    if showMenu {
                        Image(systemName: "arrow.left").font(.body).foregroundColor(.black)
                    }
                    else {
                        Image("Menu").renderingMode(.original)
                    }
                })
            )
        }
        .onAppear(perform: initialize)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
