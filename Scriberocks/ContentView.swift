
//
//  ContentView.swift
//  Scriberocks
//
//  Created by Nicholas Carducci on 5/7/23.
//

import SwiftUI
import Foundation
import Combine
extension UIScreen{
   static let screenWidth = UIScreen.main.bounds.size.width
   static let screenHeight = UIScreen.main.bounds.size.height
   static let screenSize = UIScreen.main.bounds.size
}//https://stackoverflow.com/questions/57727107/how-to-get-the-iphones-screen-width-in-swiftui
struct SymbolButton: View {
    //https://onmyway133.com/posts/how-to-pass-focusstate-binding-in-swiftui/
    var flag: FocusState<Bool>.Binding
    //@Binding public var flag: Bool
    //@Binding public var flag: FocusState<Bool>//.Binding
    //https://developer.apple.com/forums/thread/682448
    @Binding public var socialstop: Bool
    
    @AppStorage("rock")
    private var rocksData: Data = Data()
    
    @Binding public var typing: Bool
    @Binding public var message: String
    @State private var index: Int = 0
    @State private var solution: [String] = []
    @Binding public var confirmSave: Bool
    let defaults = UserDefaults.standard
    @Binding public var rocks:[String]
    var body: some View {
        HStack(alignment: .bottom) {
            //let windowScene = UIScene as? UIWindowScene
            //let screenSize: CGRect = UIScreen.main.bounds
            VStack(alignment: .leading) {
                Text(Date().formatted(.dateTime.day().month().year()))
                    .opacity(message == "" ? 1 : 0)
                    .onTapGesture {
                            withAnimation(.default.speed(0.1)) {
                                flag.wrappedValue.toggle()//just to change state
                            }
                    }
                HStack {
                    Image(systemName: "fossil.shell")
                        .imageScale(.large)
                        .foregroundColor(.accentColor)
                        .opacity(message == "" ? 1 : 0)
                        //.transition(AnyTransition.move(edge: .bottom))
                    Image(systemName: "pencil.and.outline")
                        .imageScale(.small)
                        .foregroundColor(.accentColor)
                        .opacity(message == "" ? 1 : 0)
                    Text("Scriberocks")
                        .opacity(message == "" ? 1 : 0)
                }
                HStack {
                    Text("Save +")
                        .onTapGesture {
                            guard message.isEmpty == false else { return }
                            print(message)
                            //confirmSave = true
                            //if(message == "") {
                                
                            flag.wrappedValue.toggle()//just to change state
                                confirmSave = true
                            
                            //FirebaseApp.configure()
                            //https://designcode.io/swiftui-advanced-handbook-firebase-auth
                            
                            /*db.collection("cities").document("LA").setData([
                             "message": rock,
                             "authorId": "CA"
                             ]) { err in
                             if let err = err {
                             print("Error writing document: \(err)")
                             } else {
                             print("Document successfully written!")
                             }
                             }*/
                        }
                        .confirmationDialog("Are you sure?",
                          //https://useyourloaf.com/blog/swiftui-confirmation-dialogs/
                          isPresented: $confirmSave) {
                            Button(socialstop ? "Share rock" : "Save rock", role: .destructive) {
                                solution.append(message)
                                solution.append(contentsOf: rocks)
                                defaults.set(solution, forKey: "ROCKS")
                                
                                /*let rock = Rock(getRock: message)
                                //let rock = Rock(array: roc.getRock.append("\(roc.viewerIndex):\(message)"))
                                guard let rockData = try? JSONEncoder().encode(rock) else {
                                    return
                                }//https://www.youtube.com/watch?v=tdyT_v4lwos
                                self.rocksData = rockData*/
                           }
                        }
                    Image(systemName: !typing ? "balloon" : "balloon.fill")
                        .imageScale(.medium)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.top, 9.0)
            .offset(x: 0, y: 0)//self.windowScene?.screen.bounds.size.height?
            //https://stackoverflow.com/questions/25662595/value-of-optional-type-cgfloat-not-unwrapped-error-in-swift
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/*class LatestRocks: ObservableObject {
    @Published var rock: String {
        didSet {
            UserDefaults.standard.set(rock, forKey: "rock")
        }
    }
    @Published var createdAt: Date {
        didSet {
            UserDefaults.standard.set(createdAt, forKey: "createdAt")
        }
    }
    
    init() {
        self.rock = UserDefaults.standard.object(forKey: "rock") as? String ?? ""
        self.createdAt = UserDefaults.standard.object(forKey: "createdAt") as? Date ?? Date.now
        
    }
}*/
//NSDate 00:00:00 UTC on 1 January 2001
struct SavedPage: View {
    //@AppStorage("createdAt") var createdAt: String = "2023-05-08T15:53:01-08:00"
    
    //@State public var date = Date.now
    let regularFormatter: DateFormatter = {
        let formatter = DateFormatter() //RFC3339DateFormatter
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    //@AppStorage("createdAt") var createdAt: String = "2023-05-08T15:53:01-08:00" //"\(date, formatter: regularFormatter)"
    //let keys: Array = Array(UserDefaults.standard.dictionaryRepresentation().keys)
    //https://stackoverflow.com/questions/27507213/how-to-print-nsuserdefaults-content-in-swift
    
    //https://designcode.io/swiftui-handbook-appstorage
    //https://stackoverflow.com/questions/33484312/how-to-convert-a-string-utc-date-to-nsdate-in-swift
    
    //https://stackoverflow.com/questions/65376501/update-swiftui-view-when-object-in-userdefaults-changes
    let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter() //DateFormatter
        //formatter.dateStyle = .long
        return formatter
    }()
    //@State public var saved = []
    //@State private var index: Int = 0
    //UserDefaults.standard.array(forKey: "Rocks")
    let defaults = UserDefaults.standard
    @Binding public var rocks:[String]
    //@AppStorage("rocks") var rocks: [String] = []
    //https://developer.apple.com/forums/thread/67555
    //let descending = Array(rocks.sorted().reversed())
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Saved")
                .padding(10)
            List (Array(rocks.sorted().reversed()), id: \.self){ message in
                Text(message)
            }
            
            Button("Load More Rocks"){
                //rocks = defaults.object(forKey: "Rocks") as? [String] ?? [String]()
                rocks = defaults.array(forKey: "ROCKS") as? [String] ?? [String]()
                /*let defaults = UserDefaults.standard
                let savedDict = defaults.object(forKey: "savedDict") as? [Int:String] ?? [Int:String]()
                output = savedDict*/
                //guard let rock = try?
                        //JSONDecoder().decode(Rock.self, from: rocksData) else {return}
                //https://www.hackingwithswift.com/quick-start/beginners/how-to-compute-property-values-dynamically
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct SubmitPage: View {
    
    @FocusState private var flag: Bool

    @State private var message: String = ""
    @State private var index: Int = 0
    
    @State var chatTextInput: String = ""
    @State var oldChatValue: String = ""
    @State var newChatValue: String = ""
    
    @State var typing = true
 
    //init(id: String){
        
        //self._rocksData = AppStorage(wrappedValue: false, id)
        //https://stackoverflow.com/questions/64937323/how-can-i-store-a-variable-as-the-key-of-an-appstorage-variable
    
    //var flagg: flag { get nonmutating set }
    //@State private var social = true
    @State private var socialstop = false
    @State private var confirmSave: Bool = false
    
    @Binding public var rocks:[String]
    let defaults = UserDefaults.standard
    var body: some View {
        VStack(alignment: .leading) {
            Text(message)
                .foregroundColor(flag ? .black : .blue)
                .padding(10)
            SymbolButton(
                flag: $flag,
                socialstop: $socialstop,
                typing: $typing,
                message: $message,
                confirmSave: $confirmSave,
                rocks: $rocks
            )
            TextEditor(text: $message)
                .focused($flag)
                .onSubmit {
                    guard message.isEmpty == false else { return }
                    //print(message)
                    confirmSave = true
                }
                .confirmationDialog("Are you sure?",
                  //https://useyourloaf.com/blog/swiftui-confirmation-dialogs/
                  isPresented: $confirmSave) {
                    Button(socialstop ? "Share rock" : "Save rock", role: .destructive) {
                    
                        //defaults.set([message].append(contentsOf: rocks), forKey: "ROCKS")
                        defaults.set(rocks.append(message), forKey: "ROCKS")
                   }
                 }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .lineLimit(3)
                .onChange(of: message) {newValue in
                    if typing {
                        oldChatValue += "a"
                        newChatValue += newValue.last.map{String($0)}!
                        chatTextInput = oldChatValue
                    }
                    typing.toggle()
                    
                }
                .padding(6.0)
                .border(.secondary)
                .frame(width: .infinity, height: 200)
            
            HStack {
                Toggle("Social", isOn: $socialstop)
                    .frame(alignment: .bottomTrailing)
                    .padding(10)
                    .frame(width: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView: View {
    @State public var welcomed: String = "false"
    @State public var show: String = "saved"
    //@State public var date = Date.now
    //var i = 0
    let defaults = UserDefaults.standard
    @State private var rocks: [String] = []
    var body: some View {
        VStack(alignment: .leading) {
            if(welcomed == "false"){
               Text("Open")
                    .onTapGesture {
                        withAnimation(.default.speed(0.3)) {
                            rocks = defaults.array(forKey: "ROCKS") as? [String] ?? [String]()
                            welcomed = "true"
                        }
                        
                    }
            } else { HStack(alignment: .top, spacing: 20) {
                Text("Home")
                    .onTapGesture {
                        withAnimation(.default.speed(0.3)) {
                            show = "home"
                        }
                    }
                    .padding(10)
                    .border(.black, width: show == "home" ? 1: 0)
                Text("Saved")
                    .onTapGesture {
                        withAnimation(.default.speed(0.3)) {
                            show = "saved"
                            
                            /*ForEach(1...5) { i in
                                @AppStorage(i)
                                private var rocksData: Data = Data()
                            }*/
                        }
                    }
                    .padding(10)
                    .border(.black, width: show == "saved" ? 1: 0)
                Text("Profile")
                    .onTapGesture {
                        withAnimation(.default.speed(0.3)) {
                            show = "profile"
                        }
                    }
                    .padding(10)
                    .border(.black, width: show == "profile" ? 1: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: 46)
            .padding(9.0)
            .border(.secondary)
    
                if(show == "home") {
                    SubmitPage(rocks: $rocks)
                } else if(show == "saved") {
                    SavedPage(rocks: $rocks)
                }
            }
        }
        .frame(maxWidth: UIScreen.screenWidth, maxHeight: UIScreen.screenHeight)
    }
}
