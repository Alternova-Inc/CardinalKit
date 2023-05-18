//
//  UserDataProviderDelegate.swift
//  abseil
//
//  Created by Esteban Ramos on 1/07/22.
//

import Foundation
import FirebaseAuth

public protocol UserDataProviderDelegate{
    var currentUserId: String? {get}
    var authCollection: String? {get}
    var currentUserEmail: String? {get}
    var scheduleCollection: String? {get}
    var dataBucketClinicalRecords: String { get }
    var dataBucketHealthKit: String { get }
    var dataBucketHealthKitStatistics: String { get }
    var dataBucketStorage: String { get }
    var dataBucketMetrics: String { get }
}

public class CKUserDataProvider: UserDataProviderDelegate {
    
    public var dataBucketClinicalRecords = "clinicalRecords"
    public var dataBucketHealthKit = "healthKit"
    public var dataBucketHealthKitStatistics = "healthKitStatistics"
    public var dataBucketStorage = "storage"
    public var dataBucketMetrics = "metrics"
    
    public var currentUserId: String? {
        return Auth.auth().currentUser?.uid
    }
    
    public var authCollection: String? {
        if let userId = currentUserId,
            let root = rootAuthCollection {
            return "\(root)\(userId)/"
        }
        
        return nil
    }
    
    public var scheduleCollection: String? {
        if let bundleId = Bundle.main.bundleIdentifier {
            return "/studies/\(bundleId)/schedule"
        }
        return nil
    }
    
    public var currentUserEmail: String? {
        return Auth.auth().currentUser?.email
    }
    
    fileprivate var rootAuthCollection: String? {
        if let bundleId = Bundle.main.bundleIdentifier {
            return "/studies/\(bundleId)/users/"
        }
        return nil
    }
}

public class CKUserDataProviderCustom: UserDataProviderDelegate{
    public var dataBucketClinicalRecords = "clinicalRecords"
    public var dataBucketHealthKit = "healthKit"
    public var dataBucketHealthKitStatistics = "healthKitStatistics"
    public var dataBucketStorage = "storage"
    public var dataBucketMetrics = "metrics"
    
    public var currentUserID: String
    public var studyID: String
    public var collectionDataId: String
    
    public init(currentUserID:String, studyID:String,collectionDataId: String){
        self.currentUserID = currentUserID
        self.studyID = studyID
        self.collectionDataId = collectionDataId
    }
    
    
    public var currentUserId: String? {
        return currentUserID
    }
    
    public var authCollection: String? {
        if let userId = currentUserId,
           let root = rootAuthCollection {
            return "\(root)\(userId)/"
        }
        
        return nil
    }
    
    public var scheduleCollection: String? {
        return "/studies/\(studyID)/schedule"
    }
    
    public var currentUserEmail: String? {
        return Auth.auth().currentUser?.email
    }
    
    fileprivate var rootAuthCollection: String? {
        return "/studies/\(studyID)/users/\(collectionDataId)"
    }
}
