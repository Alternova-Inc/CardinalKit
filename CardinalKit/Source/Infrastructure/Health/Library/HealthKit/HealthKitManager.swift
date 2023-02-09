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
     - Parameter withiStatistics: enable method to collect data with Statistics collection
     */
    func startHealthKitCollectionInBackground(withFrequency frequency:String, withStatistics: Bool){
        var _frequency:HKUpdateFrequency = .immediate
        if frequency == "daily" {
            _frequency = .daily
        } else if frequency == "weekly" {
            _frequency = .weekly
        } else if frequency == "hourly" {
            _frequency = .hourly
        }
        // by default cardinal kit collects all types of data
        if(withStatistics){
            self.setUpBackgroundCollectionWithStatisticCollection(withFrequency: _frequency, forTypes: types.isEmpty ? defaultTypes() : types)
        }
        else{
            self.setUpBackgroundCollection(withFrequency: _frequency, forTypes: types.isEmpty ? defaultTypes() : types)
        }
    }
    
    /**
     start healthkit data collection between specific pair of dates
        - Parameter startDate: initial date
        - Parameter endDate: final date
     */
    func startCollectionByDayBetweenDate(fromDate startDate:Date, toDate endDate:Date?, completion: @escaping () -> Void){
        self.setUpCollectionByDayBetweenDates(fromDate: startDate, toDate: endDate, forTypes: types, completion: completion)
    }
    
    /**
     start healthkit data collection between specific pair of dates
     - Parameter startDate: initial date
     - Parameter endDate: final date
     */
    func starCollectionBetweenDate(fromDate startDate:Date, toDate endDate:Date?, completion: @escaping () -> Void){
        self.setUpCollectionBetweenDates(fromDate: startDate, toDate: endDate, forTypes: types, completion: completion)
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
                CKApp.instance.infrastructure.onClinicalDataCollected(data: samples){}
            }
            healthStore.execute(query)
        }
    }
    
    //Set up collection betweenDate with statistic collection
    private func setUpCollectionBetweenDates(fromDate startDate:Date, toDate endDate:Date?, forTypes types:Set<HKSampleType>, completion: @escaping () -> Void){
        let sem = DispatchSemaphore.init(value: types.count)
        for type in types {
            sem.wait()
            collectData(forType: type, fromDate: startDate, toDate: endDate!){
                sem.signal()
            }
        }
    }
    
    private func setUpCollectionByDayBetweenDates(fromDate startDate:Date, toDate endDate:Date?, forTypes types:Set<HKSampleType>, completion: @escaping () -> Void){
        var copyTypes = types
        let element = copyTypes.removeFirst()
        
        getSources(forType: element, startDate: startDate){(sources) in
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()

            defer {
               dispatchGroup.leave()
            }
                
            VLog("Got sources for type %@", sources.count, element.identifier)
            for source in sources {
               dispatchGroup.enter()
                print("__Call Collection \(element.identifier)")
               self.collectDataDayByDay(forType: element, fromDate: startDate, toDate: endDate ?? Date(), source: source){ samples in
                   dispatchGroup.leave()
                }
            }
            dispatchGroup.notify(queue: .main, execute: {
                if(copyTypes.count>0){
                    self.setUpCollectionByDayBetweenDates(fromDate: startDate, toDate: endDate, forTypes: copyTypes, completion: completion)
                    copyTypes.removeAll()
                }
                else{
                    completion()
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
            let _startDate = Date().dayByAdding(-10)!
            self.getSources(forType: element, startDate: _startDate){ (sources) in
                let dispatchGroup = DispatchGroup()
                dispatchGroup.enter()
                defer {
                   dispatchGroup.leave()
                }
                for source in sources {
                   dispatchGroup.enter()
                    self.collectData(forType: element, fromDate: nil, toDate: Date(), source: source){ samples in
                        dispatchGroup.leave()
                    }
                }
            }
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
    
    private func setUpBackgroundCollectionWithStatisticCollection(withFrequency frequency:HKUpdateFrequency, forTypes types:Set<HKSampleType>, onCompletion:((_ success: Bool, _ error: Error?) -> Void)? = nil){
        var copyTypes = types
        let element = copyTypes.removeFirst()
        let query = HKObserverQuery(sampleType: element, predicate: nil, updateHandler: {
            (query, completionHandler, error) in
            if(copyTypes.count>0){
                self.setUpBackgroundCollection(withFrequency: frequency, forTypes: copyTypes, onCompletion: onCompletion)
                copyTypes.removeAll()
            }
            let _startDate = Date().dayByAdding(-10)!
            self.getSources(forType: element, startDate: _startDate){ (sources) in
                let dispatchGroup = DispatchGroup()
                dispatchGroup.enter()
                defer {
                    dispatchGroup.leave()
                }
                for source in sources {
                    dispatchGroup.enter()
                    self.collectData(forType: element, fromDate: nil, toDate: Date(), source: source){ samples in
                        dispatchGroup.leave()
                    }
                }
            }
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
    
    private func collectData(forType type:HKSampleType, fromDate startDate: Date? = nil, toDate endDate:Date, onCompletion:@escaping ()->Void ){
        
        let quantityType = HKQuantityTypeIdentifier(rawValue: type.identifier)
        
        queryStatisticCollectionHealthStore(forType: quantityType, fromDate: startDate!, toDate: endDate){
            collectionQuery, results, error in
            
            print("Consulta tipo: \(type.identifier)")
            print("Respuesta consulta: \(results?.statistics().capacity)")
            
            let sampleType = HKSampleType.quantityType(forIdentifier: quantityType)!
            
            self.convertStatisticsToHKSamples(statisticsCollection: results!, quantityType: sampleType,fromDate: startDate!, toDate: endDate){
                results in
                if results.count > 0 {
                    CKApp.instance.infrastructure.onHealthStatisticsDataColected(data: results){
                        print("complete statistic collection ")
                        onCompletion()
                    }
                }
                else{
                    onCompletion()
                }
                
            }
            
        }
    }
    
    private func convertStatisticsToHKSamples( statisticsCollection statistics : HKStatisticsCollection, quantityType:HKQuantityType, fromDate startDate: Date? = nil, toDate endDate:Date, onCompletion:@escaping ([HKSample])-> Void){
        
        var samples : [HKSample] = []
        
        statistics.enumerateStatistics(from: startDate!, to: endDate) { statistics, stop in
            
            if let quantity = statistics.averageQuantity() {
                let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: statistics.startDate, end: statistics.endDate)
                samples.append(sample)
            }
            if let quantity = statistics.sumQuantity() {
                
                let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: statistics.startDate, end: statistics.endDate)
                samples.append(sample)
            }
        }
        
        onCompletion(samples)
    }
    
    private func collectData(forType type:HKSampleType, fromDate startDate: Date? = nil, toDate endDate:Date, source:HKSource, onCompletion:@escaping (([HKSample])->Void)){
        print("Collecting type \(type.identifier)")
        let sourceRevision = HKSourceRevision(source: source, version: HKSourceRevisionAnyVersion)
        // By default start day is 10 days ago
        var _startDate = Date().dayByAdding(-10)!
        if let startDate = startDate {
            // if startDate is define use
            _startDate = startDate
        }
        else{
            // else get last sync revision for source
            _startDate = (self.getLastSyncDate(forType: type,forSource: sourceRevision))
        }
        var variable1 = false
        // Collect data for specific source, and specific dates
        self.queryHealthStore(forType: type, forSource: sourceRevision, fromDate: _startDate, toDate: endDate) { (query: HKSampleQuery, results: [HKSample]?, error: Error?) in
            if let error = error {
                VError("%@", error.localizedDescription)
            }
            guard let results = results, !results.isEmpty else {
                print("complete register no data type \(type.identifier)")
                onCompletion([HKSample]())
                return
            }
            self.saveLastSyncDate(forType: type, forSource: sourceRevision, date: Date())
            CKApp.instance.infrastructure.onHealthDataColected(data: results){
                print("complete register of type \(type.identifier)")
                print("complete register of type \(variable1)")
                if(!variable1){
                    onCompletion(results)
                    variable1 = true
                }
            }
        }
    }
    
    private func collectDataDayByDay(forType type:HKSampleType, fromDate startDate: Date, toDate endDate:Date,source:HKSource, onCompletion:@escaping (([HKSample])->Void)){
        collectData(forType: type, fromDate: startDate, toDate: startDate.dayByAdding(1)!,source: source){
            samples in
            let newStartDate = startDate.dayByAdding(1)!
            if newStartDate < endDate{
                self.collectDataDayByDay(forType: type, fromDate: newStartDate, toDate: endDate,source: source, onCompletion: onCompletion)
            }
            else{
                print("call completion \(type.identifier)")
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
    
    fileprivate func queryStatisticCollectionHealthStore(forType type: HKQuantityTypeIdentifier, fromDate startDate: Date, toDate endDate: Date, queryHandler: @escaping (HKStatisticsCollectionQuery, HKStatisticsCollection?, Error?) -> Void ){
        
        let quantityType = HKQuantityType.quantityType(forIdentifier: type)!
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        var options: HKStatisticsOptions = [.cumulativeSum]
        
        if(quantityType.aggregationStyle == .discreteArithmetic){
            options = [.discreteAverage]
        }
        
        let statisticsCollectionQuery = HKStatisticsCollectionQuery(quantityType: quantityType, quantitySamplePredicate: nil, options: options, anchorDate: startDate, intervalComponents: DateComponents(day:1))
        
        
        statisticsCollectionQuery.initialResultsHandler = { query, results, error in
            
            queryHandler(query,results,error)
        }
        
        healthStore.execute(statisticsCollectionQuery)
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
