//
//  ScriberocksApp.swift
//  Scriberocks
//
//  Created by Nicholas Carducci on 5/7/23.
//

import SwiftUI
//import FirebaseCore
//import FirebaseFirestore
//import FirebaseAuth

//let db = Firestore.firestore()
@main 
struct ScriberocksApp: App {
    //@UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() {
        //FirebaseApp.configure()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}//https://developer.apple.com/documentation/swiftui/text/init(_:)-9d1g4
//https://www.reddit.com/r/SwiftUI/comments/owez71/canvas_not_showing_in_xcode_12/
//https://stackoverflow.com/a/66889681/11711280

struct YourView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .previewInterfaceOrientation(.portrait)
        }
    }
}
//https://developer.apple.com/forums/thread/707322
