//
//  HealthKit.swift
//  abseil
//
//  Created by Esteban Ramos on 4/04/22.
//

import Foundation

import HealthKit

// Responsible for handling all data and requests regarding healthkit data
public class HealthKitManager{
    
    lazy var healthStore: HKHealthStore = HKHealthStore()
    var types:Set<HKSampleType> = Set([])
    var clinicalTypes:Set<HKSampleType> = Set([])
    
    init(){
        types = defaultTypes()
        clinicalTypes = healthRecordsDefaultTypes()
    }
    
    /**
     configure the types of healthkit data that will be collected
     - Parameter types: healhkit data types
     - Parameter clinicalTypes: clinical Data Types
     */
    public func configure(types: Set<HKSampleType>, clinicalTypes: Set<HKSampleType>){
        self.types = types
        self.clinicalTypes = clinicalTypes
    }
    
    /**
     start healthkit data collection in the background
        - Parameter frequency: frequency with which the data will be collected
     Options:
         daily
         weekly
         hourly
     */
    func startHealthKitCollectionInBackground(withFrequency frequency:String){
        var _frequency:HKUpdateFrequency = .immediate
        if frequency == "daily" {
            _frequency = .daily
        } else if frequency == "weekly" {
           _frequency = .weekly
        } else if frequency == "hourly" {
           _frequency = .hourly
        }
        // by default cardinal kit collects all types of data
        self.setUpBackgroundCollection(withFrequency: _frequency, forTypes: types.isEmpty ? defaultTypes() : types)
    }
    
    /**
     start healthkit data collection between specific pair of dates
        - Parameter startDate: initial date
        - Parameter endDate: final date
     */
    func startCollectionByDayBetweenDate(fromDate startDate:Date, toDate endDate:Date?){
        self.setUpCollectionByDayBetweenDates(fromDate: startDate, toDate: endDate, forTypes: types)
    }
    
    /**
     start clinical data collection
     */
    func collectAndUploadClinicalTypes(){
        self.collectClinicalTypes(for: clinicalTypes)
    }
}



extension HealthKitManager{
    
    private func collectClinicalTypes(for types: Set<HKSampleType>){
        for type in types {
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
                guard let samples = samples as? [HKClinicalRecord] else {
                    print("*** An error occurred: \(error?.localizedDescription ?? "nil") ***")
                    return
                }
                CKApp.instance.infrastructure.onClinicalDataCollected(data: samples)
            }
            healthStore.execute(query)
        }
    }
    
    
    
    private func setUpCollectionByDayBetweenDates(fromDate startDate:Date, toDate endDate:Date?, forTypes types:Set<HKSampleType>){
        var copyTypes = types
        let element = copyTypes.removeFirst()
        
        getSources(forType: element, startDate: startDate){ [weak self] (sources) in
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()

        defer {
           dispatchGroup.leave()
        }
        guard sources.count>0
           else{
           return
        }
        VLog("Got sources for type %@", sources.count)
        for source in sources {
           dispatchGroup.enter()
           self?.collectDataDayByDay(forType: element, fromDate: startDate, toDate: endDate ?? Date(), source: source){ samples in
               dispatchGroup.leave()
            }
        }
            dispatchGroup.notify(queue: .main, execute: {
                if(copyTypes.count>0){
                    self?.setUpCollectionByDayBetweenDates(fromDate: startDate, toDate: endDate, forTypes: copyTypes)
                    copyTypes.removeAll()
                }
            })
        }
        
    }
    
    private func setUpBackgroundCollection(withFrequency frequency:HKUpdateFrequency, forTypes types:Set<HKSampleType>, onCompletion:((_ success: Bool, _ error: Error?) -> Void)? = nil){
        var copyTypes = types
        let element = copyTypes.removeFirst()
        let query = HKObserverQuery(sampleType: element, predicate: nil, updateHandler: {
            (query, completionHandler, error) in
            if(copyTypes.count>0){
                self.setUpBackgroundCollection(withFrequency: frequency, forTypes: copyTypes, onCompletion: onCompletion)
                copyTypes.removeAll()
            }
            // TODO: Get Sources
//            self.collectData(forType: element, fromDate: nil, toDate: Date()){ samples in
//                print("Samples \(samples)")
//                // TODO: send Data
//            }
            completionHandler()
        })
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: element, frequency: frequency, withCompletion: { (success, error) in
            if let error = error {
                VError("%@", error.localizedDescription)
            }
            onCompletion?(success,error)
        })
    }
    
    
    
    private func collectData(forType type:HKSampleType, fromDate startDate: Date? = nil, toDate endDate:Date, source:HKSource, onCompletion:@escaping (([HKSample])->Void)){
        
        let sourceRevision = HKSourceRevision(source: source, version: HKSourceRevisionAnyVersion)
        // By default start day is 10 days ago
        var _startDate = Date().addingTimeInterval(-10)
        if let startDate = startDate {
            // if startDate is define use
            _startDate = startDate
        }
        else{
            // else get last sync revision for source
            _startDate = (self.getLastSyncDate(forType: type,forSource: sourceRevision))
        }
        // Collect data for specific source, and specific dates
        self.queryHealthStore(forType: type, forSource: sourceRevision, fromDate: _startDate, toDate: endDate) { (query: HKSampleQuery, results: [HKSample]?, error: Error?) in
            if let error = error {
                VError("%@", error.localizedDescription)
            }
            guard let results = results, !results.isEmpty else {
                onCompletion([HKSample]())
                return
            }
            self.saveLastSyncDate(forType: type, forSource: sourceRevision, date: Date())
            CKApp.instance.infrastructure.onHealthDataColected(data: results)
            onCompletion(results)
        }
        
//
//        if let startDate = startDate {
//            _startDate = startDate
//        }
        
        
//        getSources(forType: type, startDate: _startDate){ [weak self] (sources) in
//            let dispatchGroup = DispatchGroup()
//            dispatchGroup.enter()
//
//            defer {
//                dispatchGroup.leave()
//            }
//            guard sources.count>0
//                else{
//                onCompletion([HKSample]())
//                return
//            }
//            VLog("Got sources for type %@", sources.count, type.identifier)
//            for source in sources {
//                dispatchGroup.enter()
//
//            }
//        }
    }
    
    private func collectDataDayByDay(forType type:HKSampleType, fromDate startDate: Date, toDate endDate:Date,source:HKSource, onCompletion:@escaping (([HKSample])->Void)){
        collectData(forType: type, fromDate: startDate, toDate: startDate.dayByAdding(1)!,source: source){
            samples in
            let newStartDate = startDate.dayByAdding(1)!
            if newStartDate < endDate{
                self.collectDataDayByDay(forType: type, fromDate: newStartDate, toDate: endDate,source: source, onCompletion: onCompletion)
            }
            else{
                onCompletion(samples)
            }
        }
    }
    
    fileprivate func getSources(forType type: HKSampleType, startDate: Date , onCompletion: @escaping ((Set<HKSource>)->Void)) {
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate , end: Date(), options: .strictStartDate)
        let query = HKSourceQuery(sampleType: type, samplePredicate: datePredicate) {
            query, sources, error in
            if let error = error {
                VError("%@", error.localizedDescription)
            }
            if let sources = sources {
                onCompletion(sources)
            } else {
                onCompletion([])
            }
        }
        healthStore.execute(query)
    }
    
    fileprivate func queryHealthStore(forType type: HKSampleType, forSource sourceRevision: HKSourceRevision, fromDate startDate: Date, toDate endDate: Date, queryHandler: @escaping (HKSampleQuery, [HKSample]?, Error?) -> Void) {
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sourcePredicate = HKQuery.predicateForObjects(from: [sourceRevision])
        let predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [datePredicate, sourcePredicate])
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1000, sortDescriptors: [sortDescriptor]) {
            (query: HKSampleQuery, results: [HKSample]?, error: Error?) in
            queryHandler(query, results, error)
        }
        healthStore.execute(query)
    }
    
    private func saveLastSyncDate(forType type: HKSampleType, forSource sourceRevision: HKSourceRevision, date:Date){
        let lastSyncObject =
            DateLastSyncObject(
                dataType: "\(type.identifier)",
                lastSyncDate: date,
                device: "\(getSourceRevisionKey(source: sourceRevision))"
            )
        CKApp.instance.options.localDBDelegate?.saveLastSyncItem(item: lastSyncObject)
    }
    
    private func getLastSyncDate(forType type: HKSampleType, forSource sourceRevision: HKSourceRevision) -> Date
    {
        if let result = CKApp.instance.options.localDBDelegate?.getLastSyncItem(dataType: "\(type.identifier)", device: "\(getSourceRevisionKey(source: sourceRevision))"){
            return result.lastSyncDate
        }
        return Date().dayByAdding(-1)!
    }
    
    fileprivate func getSourceRevisionKey(source: HKSourceRevision) -> String {
        return "\(source.productType ?? "UnknownDevice") \(source.source.key)"
    }
}
