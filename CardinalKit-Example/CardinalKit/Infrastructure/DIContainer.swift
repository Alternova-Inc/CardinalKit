//
//  DIContainer.swift
//  CardinalKit_Example
//
//  Created by Esteban Ramos on 5/07/22.
//  Copyright © 2022 CocoaPods. All rights reserved.
//

import Foundation
import Swinject

// Class for dependency injection implementation
final class Dependencies {
    static var container:Container = {
        let container = Container()
        
        container.register(AuthLibrary.self) { _ in FirebaseAuth() }
        container.register(NetworkingLibrary.self) { _  in FirebaseStorage() }
        container.register(SurveyManager.self) { _ in ResearchKitSurveyManager()}
        
        return container
    }()
}
