//
//  ContentView.swift
//  PhoneIoT
//
//  Created by Devin Jean on 2/25/21.
//

import SwiftUI
import Network

func toHex(bytes: [UInt8]) -> String {
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

struct ContentView: View {
    @State private var macaddr: [UInt8] = [UInt8](repeating: 7, count: 10)
    @State private var password: UInt64 = 0
    
    @State private var controlsImage: UIImage = defaultImage()
    
    @State private var addresstxt: String = "10.0.0.24"
    private static let serverPort: UInt16 = 1976
    
    @State private var udp: NWConnection?
    @State private var sendThread: DispatchQueue?
    @State private var recvThread: DispatchQueue?
    @State private var hearbeatTimer: Timer?
    
    private var sendMutex: NSCondition = NSCondition()
    @State private var sendQueue: Array<Array<UInt8>> = Array()
    
    @State private var nextHeartbeat: Double = 0.0
    private static let heartbeatInterval: Double = 30
    
    private func netsbloxify(_ msg: [UInt8]) -> Array<UInt8> {
        var expanded: Array<UInt8> = Array()
        expanded.append(contentsOf: macaddr)
        expanded.append(contentsOf: [0, 0, 0, 0])
        expanded.append(contentsOf: msg)
        return expanded
    }
    private func send(_ msg: Array<UInt8>) {
        sendMutex.lock()
        sendQueue.append(msg)
        sendMutex.signal()
        sendMutex.unlock()
    }
    private func connectToServer() {
        print("connecting to \(addresstxt):\(Self.serverPort)")
        udp = NWConnection(
            host: NWEndpoint.Host(addresstxt),
            port: NWEndpoint.Port(rawValue: Self.serverPort)!,
            using: .udp)
        
        if sendThread == nil {
            sendThread = DispatchQueue(label: "send-thread")
            sendThread?.async {
                sendMutex.lock()
                while true {
                    while sendQueue.isEmpty {
                        sendMutex.wait()
                    }
                    for msg in sendQueue {
                        udp?.send(content: msg, completion: NWConnection.SendCompletion.contentProcessed { err in })
                    }
                    sendQueue.removeAll()
                }
            }
        }
        if hearbeatTimer == nil {
            hearbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { t in
                send(netsbloxify([ UInt8("I")! ]))
            }
        }
        if recvThread == nil {
            recvThread = DispatchQueue(label: "recv-thread")
            recvThread?.async {
                while true {
                    udp?.receiveMessage { msg, context, isComplete, error in
                        if msg != nil && error == nil && isComplete {
                            let content = [UInt8](msg!)
                            
                        }
                    }
                }
            }
        }
    }
    
    var body: some View {
        VStack {
            Text("PhoneIoT - \(toHex(bytes: macaddr))")
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
        }.padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
