import Foundation

public class Context: NSObject {
    private static var classes: [String: Resource.Type] = [:]
    
    let dictionary: NSMutableDictionary
    lazy var resourcePool = ResourcePool()
    
    public init(dictionary: NSMutableDictionary) {
        self.dictionary = dictionary
    }
    
    let queue = DispatchQueue(label: "vox.context.queue", attributes: .concurrent)
    
    @objc public static func registerClass(_ resourceClass: Resource.Type) {
        classes[resourceClass.resourceType.lowercased()] = resourceClass
    }
    
    func dataType() -> DataType {
        var dataType: DataType!
        
        queue.sync {
            if let array = dictionary["included"] as? NSMutableArray {
                array.forEach({ (resourceData) in
                    guard let dictionary = resourceData as? NSMutableDictionary else { fatalError("Invalid data type") }
                    mapResource(for: dictionary)
                })
            }
            
            if let data = dictionary["data"] as? NSMutableDictionary {
                let resource = mapResource(for: data)
                dataType = .resource(resource)
            } else if let data = dictionary["data"] as? NSMutableArray {
                let resources = data.compactMap({ (resourceData) -> Resource? in
                    guard let dictionary = resourceData as? NSMutableDictionary else { fatalError("Invalid data type") }
                    let resource = mapResource(for: dictionary)
                    
                    return resource
                })
                
                dataType = .collection(resources)
            } else if let errors = dictionary["errors"] as? NSMutableArray {
                let errorObjects = errors.compactMap({ (object) -> ErrorObject? in
                    guard let object = object as? [String: Any] else { return nil }
                    return ErrorObject(dictionary: object)
                })
                
                dataType = .error(errorObjects)
            } else {
                dataType = .unknown
            }
        }
        
        return dataType
    }
    
    @discardableResult func mapResource(for data: NSMutableDictionary) -> Resource? {
//        guard let id = data["id"] as? String else {
//            fatalError("Resource id must be defined")
//        }
        
        guard let type = data["type"] as? String else {
            fatalError("Resource type must be defined")
        }
        
        guard let resourceClass = self.resourceClass(for: type) else {
            return nil
        }
        
        let id = data["id"] as? String ?? UUID().uuidString
        
        let resource = resourceClass.init(context: self)
        resource.id = (id as NSString).copy() as? String
        resource.type = (type as NSString).copy() as! String
        resourcePool.addResource(resource)
        resource.object = data

        // add relationship objects into resourcePool, even though they are missing in the `included` object.
        if let relationships = data["relationships"] as? NSMutableDictionary {
            for (key, value) in relationships {
                if var type = key as? String, let dict = (value as? NSMutableDictionary) {
                    if let dataObject = dict.object(forKey: "data") {
                        if let data = dataObject as? NSMutableDictionary {
                            addRelationshipResource(type: type, data: data)
                        } else if let dataArray = dataObject as? NSMutableArray {
                            for dataInArray in dataArray {
                                if let data = dataInArray as? NSMutableDictionary {
                                    addRelationshipResource(type: type, data: data)
                                }
                            }
                        }
                    }
                }
            }
        }

        return resource
    }
    
    func resourceClass(for type: String) -> Resource.Type? {
        guard let resourceClass = Context.classes[type.lowercased()] else { return nil }
        
        return resourceClass
    }
    
    func reassign() {
        resourcePool.reassignContext(self)
    }

    private func addRelationshipResource(type: String, data: NSMutableDictionary) {
        if let resourceClass = self.resourceClass(for: type) {
            let id = data["id"] as? String ?? UUID().uuidString

            let resource = resourceClass.init(context: self)
            resource.id = (id as NSString).copy() as? String
            resourcePool.addResourceIfNotExists(resource)
        }
    }
}

enum DataType {
    case resource(Resource?)
    case collection([Resource]?)
    case error([ErrorObject])
    case unknown
}
