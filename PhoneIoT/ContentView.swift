//
//  ContentView.swift
//  PhoneIoT
//
//  Created by Devin Jean on 2/25/21.
//

import SwiftUI

func scale(point: CGPoint) -> CGPoint {
    let s = UIScreen.main.scale
    return CGPoint(x: point.x * s, y: point.y * s)
}
func scale(size: CGSize) -> CGSize {
    let s = UIScreen.main.scale
    return CGSize(width: size.width * s, height: size.height * s)
}
func scale(rect: CGRect) -> CGRect {
    CGRect(origin: scale(point: rect.origin), size: scale(size: rect.size))
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
    var core: CoreController!
    
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
            let pos = scale(point: touch.location(in: self))
            if let control = core.getControl(at: pos) {
                if !isTouchTarget(control: control) { // don't allow multiple touches on same control
                    activeTouches[touch] = TouchData(pos: pos, control: control)
                    control.mouseDown(core: core, pos: pos)
                    didSomething = true
                }
            }
        }
        
        if didSomething { core.triggerUpdate() }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var didSomething = false
        
        for touch in touches {
            let pos = scale(point: touch.location(in: self))
            if let data = activeTouches[touch] {
                if data.lastPos != pos {
                    data.lastPos = pos
                    data.control.mouseMove(core: core, pos: pos)
                    didSomething = true
                }
            }
        }
        
        if didSomething { core.triggerUpdate() }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        var didSomething = false
        
        for touch in touches {
            if let data = activeTouches.removeValue(forKey: touch) {
                data.control.mouseUp(core: core)
                didSomething = true
            }
        }
        
        if didSomething { core.triggerUpdate() }
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

struct ContentView: View {
    @StateObject var core = CoreController()
    
    var body: some View {
        NavigationView {
            ZStack {
                GeometryReader { geometry in
                    Image(uiImage: core.render(size: scale(size: geometry.size)))
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
        .onAppear(perform: core.initialize)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
