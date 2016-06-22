//
//  CoreDataController.swift
//  CoreDataController
//
//  Created by Kyle Zaragoza on 6/21/16.
//  Copyright © 2016 Kyle Zaragoza. All rights reserved.
//

import Foundation
import CoreData

class CoreDataStack {
    private var managedObjectModel: NSManagedObjectModel!
    private var coordinator: NSPersistentStoreCoordinator!
    
    /// MOC used for non-blocking writes to disk.
    private var privateDiskContext: NSManagedObjectContext!
    
    /// MOC used for displaying data to user on main thread.
    private(set) var managedObjectContext: NSManagedObjectContext!
    
    /// MOC used for performing work on a background context, `managedObjectContext` is the parent of this context.
    private(set) var backgroundWorkerContext: NSManagedObjectContext!
    
    
    // MARK: - Init
    
    /**
     Inits core data stack and calls optional callback when finished.
     - Parameter dataModelFilename: Name of .xcdatamodel file to associate w/ core data stack
     - Parameter storeFilename: Name of file which will be saved to disk, can be found in `Documents/DataStore/{storeFilename}`
     - Parameter inMemory: Set to `true` if the stack should use in-memory storage, `false` to use SQLite backed store.
     - Parameter dumpInvalidStore: Set to `true` if the original SQLite file should be deleted if it can't be opened on the first try. Only use this feature if your data is reproduceable (from server, backup, etc.).
     - Parameter finished: The closure which is called after opening the store has failed or succeeded.
     */
    init(dataModelFilename: String, storeFilename: String, inMemory: Bool = false, dumpInvalidStore: Bool = false, finished: ((success: Bool, error: NSError?) -> Void)?) {
        guard let modelURL = Bundle.main().urlForResource(dataModelFilename, withExtension: "momd") else {
            fatalError("No model to generate a store from: \(dataModelFilename).momd")
        }
        
        managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        guard managedObjectModel != nil && coordinator != nil else {
            fatalError("\(#function) Unable to create 'coordinator' || 'managedObjectModel'.")
        }
        
        // init MOCs
        managedObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        backgroundWorkerContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateDiskContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        
        // setup parents
        privateDiskContext.persistentStoreCoordinator = coordinator
        managedObjectContext.parent = privateDiskContext
        backgroundWorkerContext.parent = managedObjectContext
        
        // jump on background thread for creating persistent store
        DispatchQueue.global(attributes: .qosUserInitiated).async { [weak self] in
            if self == nil { return }
            
            let psc = self!.privateDiskContext.persistentStoreCoordinator!
            let options = [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true,
                NSSQLitePragmasOption: ["journal_mode": "DELETE"]
            ]
            let storeDirectoryUrl = NSURL.documentsDirectory().appendingPathComponent("DataStore")!
            
            // ensure directory is created
            let fileManager = FileManager()
            do {
                try fileManager.createDirectory(
                    at: storeDirectoryUrl,
                    withIntermediateDirectories: true,
                    attributes: nil)
            } catch (let error) {
                print("\(#function) Unable to create directory for CoreData store. Error: \(error)")
            }
            
            guard let storeUrl = try? storeDirectoryUrl.appendingPathComponent(storeFilename) else {
                fatalError("\(#function) Unable to create storeUrl for file name: \(storeFilename)")
            }
            
            // attempt to open the store
            let storeType = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            if inMemory {
                print("\(#function) Opening CoreData stack in memory")
            } else {
                print("\(#function) Opening CoreData stack w/ store URL: \(storeUrl)")
            }
            do {
                try psc.addPersistentStore(
                    ofType: storeType,
                    configurationName: nil,
                    at: storeUrl,
                    options: options)
            } catch (let error as NSError) {
                print("\(#function) (first try) Unable to add persistent store at url: \(storeUrl) error: \(error.localizedDescription) code: \(error.code)")
                if dumpInvalidStore == false {
                    // alert caller if not wishing to dump corrupt store
                    DispatchQueue.main.async {
                        finished?(success: false, error: error)
                    }
                    return
                } else {
                    do {
                        // dump the old store
                        print("\(#function) Dumping old store after first attempt failed")
                        try fileManager.removeItem(at: storeUrl)
                        // try once more
                        try psc.addPersistentStore(
                            ofType: storeType,
                            configurationName: nil,
                            at: storeUrl,
                            options: options)
                    } catch (let error as NSError) {
                        print("\(#function) (second try) Unable to add persistent store at url: \(storeUrl): error: \(error)")
                        DispatchQueue.main.async {
                            finished?(success: false, error: error)
                        }
                        return
                    }
                }
            }
            
            // dispatch sync, waiting for our UI thread to be ready
            DispatchQueue.main.sync {
                finished?(success: true, error: nil)
            }
        }
    }
    
    
    // MARK: - Saving
    
    /**
     Saves both main context and private context (which will save to disk).
     - NOTE: This will not save the `backgroundWorkerContext`.
     */
    func saveToDisk() {
        guard privateDiskContext.hasChanges || managedObjectContext.hasChanges else { return }
        managedObjectContext.perform { [weak self] in
            guard self != nil else { return }
            // save main context
            do {
                try self!.managedObjectContext.save()
            } catch (let error as NSError) {
                print("\(#function) Failed to save main context: \(error)")
            }
            print("\(#function) Saved main context")
            // save to disk
            self!.privateDiskContext.perform { [weak self] in
                guard self != nil else { return }
                do {
                    try self!.privateDiskContext.save()
                } catch (let error as NSError) {
                    print("\(#function) Failed to save to disk: \(error)")
                }
                print("\(#function) Saved to disk")
            }
        }
    }
}


// MARK: - Documents Directory Getter

extension NSURL {
    class func documentsDirectory() -> NSURL {
        return FileManager.default().urlsForDirectory(.documentDirectory, inDomains: .userDomainMask).last!
    }
}
