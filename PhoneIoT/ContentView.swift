//
//  ContentView.swift
//  PhoneIoT
//
//  Created by Devin Jean on 2/25/21.
//

import SwiftUI

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
    
    @State private var addresstxt: String = "123"
    
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
