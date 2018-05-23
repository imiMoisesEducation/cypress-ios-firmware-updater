//
//  BLEProtocols
//
//  Coded by Moises Lozada.  on 25/1/18.
import Foundation
import CoreBluetooth

protocol BLEServices{
    static var services:[CBUUID]{get}
    var uuidString:String{get}
}

protocol PrBLEHashableCharacteristic:Hashable{
    var uuid:String{get set}
    var characteristic:IsBLECharacteristic?{get set}
}

extension PrBLEHashableCharacteristic{
    var hashValue: Int{
        return self.uuid.hashValue
    }
    
    static public func ==(lhs:Self,rhs:Self)->Bool{
        return lhs.uuid == rhs.uuid
    }
}

protocol BLECharacteristicManager:class{
    subscript(_ uuid: String) -> CBCharacteristic? {get set}
    func set(characteristic: IsBLECharacteristic)
    func getCharacteristic(UUID: String) -> CBCharacteristic?
    func updateNotificationState(UUID: String,state:Bool)
    func resubscribeNotifications()
    var peripheral: IsPeripheral!{get}
    init(peripheral: IsPeripheral)
}
extension BLECharacteristicManager{
    public subscript(_ uuid:String)->CBCharacteristic?{
        get{
            return self.getCharacteristic(UUID: uuid)
        }
        set{
            guard let characteristic = newValue else{
                return
            }
            self.set(characteristic: characteristic)
        }
    }
}

public protocol IsPeripheral:class{
    var uuid: String{get}
    func writeValue(_ data: Data, for: IsBLECharacteristic, type: CBCharacteristicWriteType)
    func readValue(for: IsBLECharacteristic)
    func setNotifyValue(_ bool: Bool, for: IsBLECharacteristic)
}

extension CBPeripheral:IsPeripheral{
    public var uuid: String{
        get{
            return self.identifier.uuidString
        }
    }
    public func writeValue(_ data: Data, for ch: IsBLECharacteristic, type: CBCharacteristicWriteType) {
        self.writeValue(data, for: ch as! CBCharacteristic, type: type)
    }
    public func readValue(for ch: IsBLECharacteristic) {
        self.readValue(for: ch as! CBCharacteristic)
    }
    public func setNotifyValue(_ bool: Bool, for ch: IsBLECharacteristic) {
        self.setNotifyValue(bool, for: ch as! CBCharacteristic)
    }
}

protocol isConvertibleFromData{
    static func parse(from data: Data?)->Self?
}
extension isConvertibleFromData{
    static func parse(from data: Data?)->Self?{
        return data?.withUnsafeBytes({ (pointer:UnsafePointer<Self>) -> Self in
            return pointer.pointee
        })
    }
}
extension String: isConvertibleFromData{
    static func parse(from data: Data?)->String?{
        guard data != nil else{
            return nil
        }
        return String.init(data: data!, encoding: .utf8)
    }
}

extension Data:isConvertibleFromData{
    static func parse(from data: Data?)->Data?{
        return data
    }
}

protocol isConvertibleToData{
    static func parse(from this:Self)->Data
}

extension isConvertibleToData{
    static func parse(from this:Self)->Data{
        var this = this
        return Data.init(buffer: UnsafeBufferPointer<Self>.init(start: &this, count: 1))
    }
}

extension String: isConvertibleToData{
    static func parse(from this:String)->Data{
        return this.data(using: .utf8)!
    }
}

extension Data: isConvertibleToData{
    static func parse(from this:Data)->Data{
        return this
    }
}

extension UInt8: isConvertibleFromData,isConvertibleToData{}
extension UInt16: isConvertibleFromData,isConvertibleToData{}
extension UInt32: isConvertibleFromData,isConvertibleToData{}
extension UInt64: isConvertibleFromData,isConvertibleToData{}
extension Int8: isConvertibleFromData,isConvertibleToData{}
extension Int16: isConvertibleFromData,isConvertibleToData{}
extension Int32: isConvertibleFromData,isConvertibleToData{}
extension Int64: isConvertibleFromData,isConvertibleToData{}
extension Float32: isConvertibleFromData,isConvertibleToData{}
extension FloatLiteralType: isConvertibleFromData,isConvertibleToData{}
extension Bool: isConvertibleFromData,isConvertibleToData{}
