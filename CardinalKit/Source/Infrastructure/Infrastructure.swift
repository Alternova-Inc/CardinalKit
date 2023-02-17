//
//  Infrastructure.swift
//  CardinalKit
//
//  Created by Esteban Ramos on 17/04/22.
//

import Foundation
import CommonCrypto

// Infrastructure layer of DDD architecture
/// This layer will be the layer that accesses external services such as database, messaging systems and email services.

internal class Infrastructure {
    // Managers
    // Responsible for handling all data and requests regarding healthkit data
    var healthKitManager:HealthKitManager
    // Permissions
    // In charge of managing the necessary permissions to manipulate healthkit data (implemented in the application layer)
    var healthPermissionProvider:Healthpermissions
    // OpenMHealthSerializer
    // in charge of transforming healthkit data into an openMhealth format
    var mhSerializer:OpenMHSerializer
    
    
    init(){
        healthKitManager = HealthKitManager()
        mhSerializer = CKOpenMHSerializer()
        healthPermissionProvider = Healthpermissions()
        healthPermissionProvider.configure(types: healthKitManager.defaultTypes(), clinicalTypes: healthKitManager.healthRecordsDefaultTypes())
        _ = NetworkTracker.shared
        
    }
    
    func configure(types: Set<HKSampleType>, clinicalTypes: Set<HKSampleType>){
        healthPermissionProvider.configure(types: types, clinicalTypes: clinicalTypes)
        healthKitManager.configure(types: types, clinicalTypes: clinicalTypes)
    }
    
    // Prompt user for healthkit permissions
    func getHealthPermission(completion: @escaping (Result<Bool, Error>) -> Void){
        healthPermissionProvider.getHealthPermissions(completion: completion)
    }
    
    // Ask the user for clinical permissions
    func getClinicalPermission(completion: @escaping (Result<Bool, Error>) -> Void){
        healthPermissionProvider.getRecordsPermissions(completion: completion)
    }
    
    // start healthkit data collection in the background
    func startBackgroundDeliveryData(){
        healthPermissionProvider.getHealthPermissions{ result in
            switch result{
            case .success(let success):
                if success {
                    self.healthKitManager.startHealthKitCollectionInBackground(withFrequency: "", withStatistics: false)
                }
            case .failure(let error):
                print("error \(error)")
            }
        }
    }
    
    // start healthkit data collection in the background using Statistics Collection
    func startBackgroundDeliveryDataWithStatisticCollection(){
        healthPermissionProvider.getHealthPermissions{ result in
            switch result{
            case .success(let success):
                if success {
                    self.healthKitManager.startHealthKitCollectionInBackground(withFrequency: "", withStatistics: true)
                }
            case .failure(let error):
                print("error \(error)")
            }
        }
    }
    
    // get data from healthkit on a specific date
    func collectData(fromDate startDate:Date, toDate endDate: Date, completion: @escaping () -> Void){
        healthPermissionProvider.getAllPermissions(){ result in
            switch result{
            case .success(let success):
                if success {
                    self.healthKitManager.startCollectionByDayBetweenDate(fromDate: startDate, toDate: endDate, completion: completion)
                    self.healthKitManager.collectAndUploadClinicalTypes()
                }
            case .failure(let error):
                print("error \(error)")
            }
        }
    }
    
    //Get Data from healhkit on a specific date using StatistiCollection
    func collectDataWithStatisticCollection(fromDate startDate:Date, toDate endDate: Date, completion: @escaping () -> Void){
        healthPermissionProvider.getAllPermissions(){ result in
            switch result{
            case .success(let success):
                if success {
                    self.healthKitManager.starCollectionBetweenDateWithStatisticCollection(fromDate: startDate, toDate: endDate, completion: completion)
                }
            case .failure(let error):
                print("error \(error)")
            }
        }
    }
    
    //collect all clinical data
    func collectClinicalData(){
        healthPermissionProvider.getAllPermissions(){ result in
            switch result{
            case .success(let success):
                if success {
                    self.healthKitManager.collectAndUploadClinicalTypes()
                }
            case .failure(let error):
                print("error \(error)")
            }
        }
    }
    
    // function called when new data is received from healthkit
    func onHealthDataColected(data:[HKSample], onCompletion:@escaping ()->Void){
        do{
            // Transfom Data in OPENMHealth Format
            let samplesArray:[[String: Any]] = try mhSerializer.json(for: data)
            for sample in samplesArray{
                
                var identifier = "HKData"
                if let header = sample["header"] as? [String:Any],
                   let id = header["id"] as? String{
                    identifier = id
                }
                
                let sampleToData = try JSONSerialization.data(withJSONObject: sample, options: [])
                CreateAndPerformPackage(type: .hkdata, data: sampleToData, identifier: identifier, onCompletion: onCompletion)
            }
        }
        catch{
            print("Error Transform Data: \(error)")
        }
    }
    
    // function called when new data is received from healthkit
    func onHealthStatisticsDataColected(data:[HKSample],isStatisticCollection: Bool? = nil, onCompletion:@escaping ()->Void){
        
        let queue = DispatchQueue.main
        let group = DispatchGroup()
        
        do{
            var _isStatisticsCollection = false
            if let isStatisticCollection = isStatisticCollection {
                _isStatisticsCollection = isStatisticCollection
            }
            
            // Transfom Data in OPENMHealth Format
            let samplesArray:[[String: Any]] = try mhSerializer.json(for: data)
            for sample in samplesArray{
                
                
                var identifier = "HKDataStatistics"
                
                if let body = sample["body"] as? [String:Any],
                   let timeframe = body["effective_time_frame"] as? [String:Any],
                   let timeInterval = timeframe["time_interval"] as? [String:Any],
                   let startDate = timeInterval["start_date_time"] as? String,
                   let quantity = body["quantity_type"] as? String{
                    let combine = quantity + startDate
                    let hash = md5(data: combine.data(using: .utf8)!)
                    
                    identifier = hash
                }
                
                if let body = sample["body"] as? [String:Any],
                   let timeframe = body["effective_time_frame"] as? [String:Any],
                   let dateTime = timeframe["date_time"] as? String,
                   let quantity = body["quantity_type"] as? String{
                    let combine = quantity + dateTime
                    let hash = md5(data: combine.data(using: .utf8)!)
                    identifier = hash
                }
                
                var sampleUpdate = sample
                
                if var header = sampleUpdate["header"] as? [String:Any]{
                    
                    header.updateValue(identifier, forKey: "id")
                    sampleUpdate.updateValue(header, forKey: "header")
                }
                
                if(_isStatisticsCollection){
                    let data : [String:Any] = ["isStatisticCollection" : _isStatisticsCollection]
                    sampleUpdate.append(data)
                }
                
                let sampleToData = try JSONSerialization.data(withJSONObject: sampleUpdate, options: [])
                
                group.enter()
                
                queue.async {
                    self.CreateAndPerformPackage(type: .hkdata, data: sampleToData, identifier: identifier, isStatisticCollection: _isStatisticsCollection){
                        group.leave()
                    }
                }
            }
            group.wait()
            onCompletion()
            print("Upload Process is complete")
        }
        catch{
            print("Error Transform Data: \(error)")
        }
    }
    
    func md5(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    // function called when a new clinical data is received
    func onClinicalDataCollected(data: [HKClinicalRecord], onCompletion:@escaping ()->Void){
        for sample in data {
            guard let resource = sample.fhirResource else { continue }
            let data = resource.data
            let identifier = resource.resourceType.rawValue + "-" + resource.identifier
            CreateAndPerformPackage(type: .clinicalData, data: data, identifier: identifier, onCompletion: onCompletion)
            
        }
    }
    
    /**
     to send data from healthkit to the external database we use the package model that is first saved in a local database,
     This function creates the package and saves it to then try to send it to the external database.
     
     - Parameter Type: type of package that is required to be sent
     PackageType:
     case hkdata = "HKDATA"
     case metricsData = "HKDATA_METRICS"
     case clinicalData = "HKCLINICAL"
     case hkdataStatistics="HKDATASTATISTICS"
     
     - Parameter data: the data to send
     - Parameter identifier: unique package identifier
     */
    private func CreateAndPerformPackage(type: PackageType, data:Data, identifier: String, isStatisticCollection: Bool? = nil,  onCompletion:@escaping ()->Void){
        do{
            let packageName = identifier
            let package = try Package(packageName, type: type, identifier: packageName, data: data)
            var networkObject = NetworkRequestObject.findOrCreateNetworkRequest(package)
            
            if let isStatisticCollection = isStatisticCollection{
                networkObject.lastAttempt = nil
            }
            
            try networkObject.perform(){ complete, Error in
                onCompletion()
            }
        }
        catch{
            print("[upload] ERROR " + error.localizedDescription)
        }
    }
}
