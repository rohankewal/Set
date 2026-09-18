#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Pushes the complete schema to the CloudKit **Development** environment.
///
/// CloudKit only learns a record type or field once a record using it syncs, so
/// a Development schema built by ordinary use is usually missing something (a
/// set type nobody logged, an empty optional). Deploying that to Production
/// ships a schema the release build can't write to, and sync fails silently for
/// every user. This creates every type and field up front.
///
/// Run once before each schema deploy, with `--init-cloudkit-schema`, on a
/// device or simulator signed into iCloud. Then deploy in the CloudKit Console.
/// DEBUG-only: Release builds must never touch the schema.
enum CloudKitSchema {
    static let containerIdentifier = "iCloud.com.rohankewalramani.Set"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--init-cloudkit-schema")
    }

    /// Runs off the main thread against a throwaway store, so launch never waits
    /// on the network (iOS kills an app stuck on its launch screen for ~20s when
    /// no debugger is attached) and the real store is never involved.
    static func initializeInBackground() {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: SetSchemaV1.models) else {
            print("[CloudKitSchema] Could not build a Core Data model from the SwiftData schema.")
            return
        }
        nonisolated(unsafe) let unsafeModel = model
        print("[CloudKitSchema] Starting in the background…")
        Thread.detachNewThread {
            run(model: unsafeModel)
        }
    }

    private nonisolated static func run(model: NSManagedObjectModel) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CloudKitSchema", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let description = NSPersistentStoreDescription(url: directory.appending(path: "Schema.store"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "Schema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            print("[CloudKitSchema] Failed: store didn't load: \(loadError)")
            return
        }

        do {
            try container.initializeCloudKitSchema()
            print("[CloudKitSchema] Development schema initialized. Remove the launch argument, then deploy it to Production in the CloudKit Console.")
        } catch {
            print("[CloudKitSchema] Failed: \(error)")
        }

        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }
}
#endif
