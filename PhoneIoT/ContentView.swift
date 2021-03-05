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
func defaultImage() -> UIImage {
    let size = CGSize(width: 50, height: 50)
    UIGraphicsBeginImageContext(size)
    
    let context = UIGraphicsGetCurrentContext()!
    context.setFillColor(gray: 0.0, alpha: 1.0)
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

struct ContentView: View {
    @State private var macaddr: [UInt8] = [UInt8](repeating: 0, count: 6)
    @State private var password: UInt64 = 0
    @State private var passwordExpiry: Double = Double.infinity
    private static let passwordLifecycle: Double = 60 * 60
    
    @State private var controlsImage: UIImage = defaultImage()
    
    @State private var addresstxt: String = "10.0.0.24"
    private static let serverPort: UInt16 = 1976
    
    @State private var udp: NWConnection?
    @State private var hearbeatTimer: Timer?
    private static let heartbeatInterval: Double = 30
    
    private func getPassword() -> UInt64 {
        let time = getTime()
        if time < passwordExpiry {
            return password
        }
        
        password = UInt64.random(in: 0...0x7fffffffffffffff)
        passwordExpiry = time + Self.passwordLifecycle
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
//        udp!.stateUpdateHandler = { state in
//            switch (state) {
//            case .ready: print("udp state: ready")
//            case .setup: print("udp state: setup")
//            case .cancelled: print("udp state: cancelled")
//            case .preparing: print("udp state: preparing")
//            default: print("udp state: UNKNOWN OR ERR")
//            }
//        };
        udp!.start(queue: .global())
        
        // start listening for (complete) packets
        udp!.receiveMessage { msg, context, isComplete, error in
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
                case UInt8(ascii: "a"): send(netsbloxify([ content[0] ]))
                default: print("unrecognized request code: \(content[0])")
                }
            }
        }
        
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
    }
    var body: some View {
        VStack {
            Text("PhoneIoT - \(toHex(bytes: macaddr[...]))")
                .font(.system(size: 16))
            Text("password - \(String(format: "%016x", password))")
                .font(.system(size: 14))
            
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
            
            TextField("Server Address: ", text: $addresstxt)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .border(Color.black)
            
            HStack {
                Button("Connect") {
                    connectToServer()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(Color.white)
                
                Spacer()
                
                Button("New Password") {
                    
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(Color.white)
            }
        }
        .padding()
        .onAppear(perform: initialize)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
