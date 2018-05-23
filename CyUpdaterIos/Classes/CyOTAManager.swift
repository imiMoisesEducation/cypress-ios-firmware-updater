//
//  CyOtaManager.swift
//
//  Coded by Moises Lozada.  on 23/4/18.

import Foundation
import CoreBluetooth

protocol CyBLEOTAManagerDelegate{
    func cyBLEOtaManager(manager: CyBLEOTAManager,notification:CyBLEOTAManagerNotification)
}

enum CyBLEOTAManagerNotification{
    case error(CyBLEOTAManagerError)
    case enterBootloader(response: BLEModelOTABotloaderResponse)
    case getFlashSize(response: BLEModelOTAFashSizeResponse)
    case verifyChecksum(succeeded: Bool)
    case sendData(suceeded: Bool)
    case programRow(suceeded:Bool)
    case verifyRow(checksum:UInt8)
    case exitBootloader
}

public enum CyBLEOTAManagerError:Error{
    case parserError
    var localizedDescription: String{
        switch self{
        case .parserError:
            return "ENTER_BOTLOADER characteristic response parser had an error"
        }
    }
}

final public class CyBLEOTAManager:BLECharacteristicManager{
    
    weak var peripheral: IsPeripheral!
    var delegate: CyBLEOTAManagerDelegate? = nil
    internal var didPreviouslyFindCharacteristic: Bool = false
    internal var foundCharacteristic:  ((CyBLEOTAManager)->())? = nil
    internal var characteristic: IsBLECharacteristic? = nil
    
    internal var state: CyBLEOtaCommand?{
        return CyBLEOtaCommand.parse(from: characteristic?.data)
    }
    
    var lastCommandSucceeded = false
    var verifyRowLastVal: Data? = nil
    func setDidFindUpdateCharacteristicHandler(_ callback:@escaping (CyBLEOTAManager)->()){
        self.foundCharacteristic = callback
        if didPreviouslyFindCharacteristic{
            callback(self)
        }
    }
    
    func set(characteristic: IsBLECharacteristic){
        if characteristic.uuidString.lowercased() == CyOTAUUIDCharacteristic.lowercased(){
            if case Optional.none = lastExecutedCommand {
                if self.characteristic == nil{
                    self.characteristic = characteristic
                    self.notify(true)
                    self.foundCharacteristic?(self)
                    self.didPreviouslyFindCharacteristic = true
                    return
                }else{
                    return
                }
            }
            self.characteristic = characteristic
            guard let state = self.state else{
                return
            }
            if case CyBLEOtaCommand.SUCCESS = state{
                lastCommandSucceeded = true
                    switch lastExecutedCommand{
                    case .some(.VERIFY_CHECKSUM):
                        guard let data = characteristic.data, data != verifyRowLastVal else{
                            return
                        }
                        verifyRowLastVal = nil
                        let checksum:UInt8 = data[4]
                        self.delegate?.cyBLEOtaManager(manager: self, notification: .verifyChecksum(succeeded: checksum > 0))
                    case .some(.GET_FLASH_SIZE):
                        if self.characteristic!.data!.count < 15{
                            let flashSizeResponse = BLEModelOTAFashSizeResponse.init(characteristic: characteristic)
                            self.delegate?.cyBLEOtaManager(manager: self, notification: .getFlashSize(response: flashSizeResponse))
                        }
                    case .some(.SEND_DATA):
                        if self.characteristic!.data!.count == 7{
                            self.delegate?.cyBLEOtaManager(manager: self, notification: .sendData(suceeded: true))
                        }
                    case .some(.ENTER_BOOTLOADER):
                        if self.characteristic!.data!.count > 8{
                            if let response = BLEModelOTABotloaderResponse.init(characteristic: characteristic){
                               self.delegate?.cyBLEOtaManager(manager: self, notification: .enterBootloader(response: response))
                            }
                        }
                    case .some(.PROGRAM_ROW):
                        if self.characteristic!.data!.count <= 7{
                            self.delegate?.cyBLEOtaManager(manager: self, notification: .programRow(suceeded: true))
                        }
                    case .some(.VERIFY_ROW):
                        guard let data = characteristic.data, data.count == 8 else{
                            return
                        }
                        verifyRowLastVal = characteristic.data!
                        let checksum: UInt8 = data[4]
                        self.delegate?.cyBLEOtaManager(manager: self, notification: .verifyRow(checksum: checksum))
                    case .some(.EXIT_BOOTLOADER):
                        self.delegate?.cyBLEOtaManager(manager: self, notification: .exitBootloader)
                    default:
                        break
                    }
            }else if case CyBLEOtaCommand.FAILED = state{
                lastCommandSucceeded = false
                    switch lastExecutedCommand{
                    case .some(.SEND_DATA):
                        self.delegate?.cyBLEOtaManager(manager: self, notification: .sendData(suceeded: false))
                    case .some(.PROGRAM_ROW):
                        self.delegate?.cyBLEOtaManager(manager: self, notification: .programRow(suceeded: false))
                    case .some(.EXIT_BOOTLOADER):
                        self.delegate?.cyBLEOtaManager(manager: self, notification: .exitBootloader)
                    default:
                        break
                }
            }
        }
        
    }
    
    func getCharacteristic(UUID: String) -> CBCharacteristic?{
        if UUID == CyOTAUUIDCharacteristic{
            return self.characteristic as? CBCharacteristic
        }
        return nil
    }
    
    internal var lastExecutedCommand: CyBLEOtaCommand? = nil
    func execute(command: CyBLEOtaCommand){
        self.lastExecutedCommand = command
        self.write(value: command)
    }
    
    func updateNotificationState(UUID: String,state:Bool){}
    func resubscribeNotifications(){}
    required public init(peripheral:IsPeripheral){
        self.peripheral = peripheral
    }
    
    internal func write(value:CyBLEOtaCommand){
        guard let characteristic = characteristic else{return}
        var data:Data!
        data = CyBLEOtaCommand.parse(from: value)
        peripheral?.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    internal func notify(_ notify: Bool){
        guard let characteristic = self.characteristic, characteristic.isNotifiable || characteristic.isIndicable else{return}
        self.peripheral?.setNotifyValue(notify, for: characteristic)
    }
}

extension CyBLEOTAManager:Equatable{
    static public func ==(lhs:CyBLEOTAManager,rhs:CyBLEOTAManager)->Bool{
        return lhs.peripheral.uuid == rhs.peripheral.uuid
    }
}

fileprivate let CyOTAUUIDCharacteristic = "00060001-F8CE-11E4-ABF4-0002A5D5C51B"

enum CyBLEOtaCommand: isConvertibleFromData, isConvertibleToData{
    
    case VERIFY_CHECKSUM(cs: CyOtaCommandsChecksumType)
    case GET_FLASH_SIZE(cs: CyOtaCommandsChecksumType,data:Set<CommandData>)
    case SEND_DATA(cs: CyOtaCommandsChecksumType,data:Set<CommandData>)
    case ENTER_BOOTLOADER(cs: CyOtaCommandsChecksumType)
    case PROGRAM_ROW(cs: CyOtaCommandsChecksumType,data:Set<CommandData>,size:UInt8)
    case VERIFY_ROW(cs: CyOtaCommandsChecksumType,data:Set<CommandData>)
    case EXIT_BOOTLOADER(cs: CyOtaCommandsChecksumType)
    case SUCCESS
    case FAILED
    
    static internal let cmdStartByte:UInt8 = 0x1
    static internal let cmdEndByte:UInt8 = 0x17
    static internal let cmdMinSize = 7
    
    var maxDataSize:UInt8{
        return 133
    }
    
    var dataLenght: UInt8{
        switch self{
        case .ENTER_BOOTLOADER, .VERIFY_CHECKSUM,.EXIT_BOOTLOADER:
            return 0
        case .GET_FLASH_SIZE:
            return 1
        case .SEND_DATA:
            return self.maxDataSize
        case .VERIFY_ROW:
            return 3
        case .PROGRAM_ROW(_,_,let size):
            return size + 3
        default:
            return 0
        }
    }
    
    var code: UInt16{
        switch self {
        case .VERIFY_CHECKSUM:
            return 0x31
        case .GET_FLASH_SIZE:
            return 0x32
        case .SEND_DATA:
            return 0x37
        case .ENTER_BOOTLOADER:
            return 0x38
        case .PROGRAM_ROW:
            return 0x39
        case .VERIFY_ROW:
            return 0x3A
        case .EXIT_BOOTLOADER:
            return 0x3B
        case .SUCCESS:
            return 0x00
        case .FAILED:
            return 0x01
        }
    }
    
    enum CommandData:Hashable{
        case flashArrayID(UInt8)
        case flashRowNumber(UInt16)
        case rowData(Array<String>)
        
        var hashValue: Int{
            switch self {
            case .flashArrayID:
                return 0
            case .flashRowNumber:
                return 1
            case .rowData:
                return 2
            }
        }
    }
    
    var data:Set<CommandData>?{
        switch  self {
        case let .GET_FLASH_SIZE(_,data),
             let .SEND_DATA(_,data),
             let .PROGRAM_ROW(_,data,_),
             let .VERIFY_ROW(_,data):
             return data
        case .ENTER_BOOTLOADER, .SUCCESS, .FAILED,.VERIFY_CHECKSUM,.EXIT_BOOTLOADER:
            return nil
        }
    }
    
    var checksumType: CyOtaCommandsChecksumType{
        switch  self {
        case let .VERIFY_CHECKSUM(cs),
             let .GET_FLASH_SIZE(cs,_),
             let .SEND_DATA(cs,_),
             let .PROGRAM_ROW(cs,_,_),
             let .VERIFY_ROW(cs,_),
             let .EXIT_BOOTLOADER(cs),
             let .ENTER_BOOTLOADER(cs):
            return cs
        case .SUCCESS, .FAILED:
            return .null
        }
    }
    
    static var table:[Int32] = [
        0x0000, 0xC0C1, 0xC181, 0x0140, 0xC301, 0x03C0, 0x0280, 0xC241,
        0xC601, 0x06C0, 0x0780, 0xC741, 0x0500, 0xC5C1, 0xC481, 0x0440,
        0xCC01, 0x0CC0, 0x0D80, 0xCD41, 0x0F00, 0xCFC1, 0xCE81, 0x0E40,
        0x0A00, 0xCAC1, 0xCB81, 0x0B40, 0xC901, 0x09C0, 0x0880, 0xC841,
        0xD801, 0x18C0, 0x1980, 0xD941, 0x1B00, 0xDBC1, 0xDA81, 0x1A40,
        0x1E00, 0xDEC1, 0xDF81, 0x1F40, 0xDD01, 0x1DC0, 0x1C80, 0xDC41,
        0x1400, 0xD4C1, 0xD581, 0x1540, 0xD701, 0x17C0, 0x1680, 0xD641,
        0xD201, 0x12C0, 0x1380, 0xD341, 0x1100, 0xD1C1, 0xD081, 0x1040,
        0xF001, 0x30C0, 0x3180, 0xF141, 0x3300, 0xF3C1, 0xF281, 0x3240,
        0x3600, 0xF6C1, 0xF781, 0x3740, 0xF501, 0x35C0, 0x3480, 0xF441,
        0x3C00, 0xFCC1, 0xFD81, 0x3D40, 0xFF01, 0x3FC0, 0x3E80, 0xFE41,
        0xFA01, 0x3AC0, 0x3B80, 0xFB41, 0x3900, 0xF9C1, 0xF881, 0x3840,
        0x2800, 0xE8C1, 0xE981, 0x2940, 0xEB01, 0x2BC0, 0x2A80, 0xEA41,
        0xEE01, 0x2EC0, 0x2F80, 0xEF41, 0x2D00, 0xEDC1, 0xEC81, 0x2C40,
        0xE401, 0x24C0, 0x2580, 0xE541, 0x2700, 0xE7C1, 0xE681, 0x2640,
        0x2200, 0xE2C1, 0xE381, 0x2340, 0xE101, 0x21C0, 0x2080, 0xE041,
        0xA001, 0x60C0, 0x6180, 0xA141, 0x6300, 0xA3C1, 0xA281, 0x6240,
        0x6600, 0xA6C1, 0xA781, 0x6740, 0xA501, 0x65C0, 0x6480, 0xA441,
        0x6C00, 0xACC1, 0xAD81, 0x6D40, 0xAF01, 0x6FC0, 0x6E80, 0xAE41,
        0xAA01, 0x6AC0, 0x6B80, 0xAB41, 0x6900, 0xA9C1, 0xA881, 0x6840,
        0x7800, 0xB8C1, 0xB981, 0x7940, 0xBB01, 0x7BC0, 0x7A80, 0xBA41,
        0xBE01, 0x7EC0, 0x7F80, 0xBF41, 0x7D00, 0xBDC1, 0xBC81, 0x7C40,
        0xB401, 0x74C0, 0x7580, 0xB541, 0x7700, 0xB7C1, 0xB681, 0x7640,
        0x7200, 0xB2C1, 0xB381, 0x7340, 0xB101, 0x71C0, 0x7080, 0xB041,
        0x5000, 0x90C1, 0x9181, 0x5140, 0x9301, 0x53C0, 0x5280, 0x9241,
        0x9601, 0x56C0, 0x5780, 0x9741, 0x5500, 0x95C1, 0x9481, 0x5440,
        0x9C01, 0x5CC0, 0x5D80, 0x9D41, 0x5F00, 0x9FC1, 0x9E81, 0x5E40,
        0x5A00, 0x9AC1, 0x9B81, 0x5B40, 0x9901, 0x59C0, 0x5880, 0x9841,
        0x8801, 0x48C0, 0x4980, 0x8941, 0x4B00, 0x8BC1, 0x8A81, 0x4A40,
        0x4E00, 0x8EC1, 0x8F81, 0x4F40, 0x8D01, 0x4DC0, 0x4C80, 0x8C41,
        0x4400, 0x84C1, 0x8581, 0x4540, 0x8701, 0x47C0, 0x4680, 0x8641,
        0x8201, 0x42C0, 0x4380, 0x8341, 0x4100, 0x81C1, 0x8081, 0x4040,
    ]
    
    func checksum(commandPacket: Array<UInt8>, size: Int)->UInt16{
        switch self.checksumType {
        case .checksum:
            var checksum:Int32 = 0
            var size = size
            while(size > 0){
                size -= 1
                checksum += Int32(commandPacket[size] & 0xFF)
            }
            return UInt16.init(UInt32.init(bitPattern: (Int32(1) + ~checksum) & 0xffff))
        case .crc16:
            var crc:Int32 = 0x0000
            for byte in commandPacket{
                crc = (crc >>>> Int32(8)) ^ CyBLEOtaCommand.table[(Int(crc) ^ Int(byte)) & 0xff]
            }
            return UInt16.init(UInt32.init(bitPattern: crc & 0xffff))
        default:
            break
        }
        return 0
    }
    
    func createCommandPacket()->Data{
        var bitPosition = 0
        var commandPacket = Array<UInt8>.init(repeating: 0, count: CyBLEOtaCommand.cmdMinSize + Int(self.dataLenght))
        
        commandPacket[bitPosition] = CyBLEOtaCommand.cmdStartByte
        bitPosition += 1
        commandPacket[bitPosition] = UInt8(self.code & 0xff)
        bitPosition += 1
        commandPacket[bitPosition] = self.dataLenght
        bitPosition += 1
        commandPacket[bitPosition] = UInt8(self.code >> 8)
        bitPosition += 1
        
        switch self {
        case .GET_FLASH_SIZE:
            commandPacket[bitPosition] = self.data!.getFlashArrayID!
            bitPosition += 1
            break
        case .PROGRAM_ROW,
             .VERIFY_ROW:
            commandPacket[bitPosition] = self.data!.getFlashArrayID!
            bitPosition += 1
            let flashRowNumber: UInt16 = self.data!.getFlashRowNumber!
            commandPacket[bitPosition] = UInt8(flashRowNumber & 0xff)
            bitPosition += 1
            commandPacket[bitPosition] = UInt8(flashRowNumber >> 8)
            bitPosition += 1
            if case CyBLEOtaCommand.PROGRAM_ROW = self{fallthrough}
        case .SEND_DATA:
            var data:Array<String> = self.data!.getRowData!
            for i in 0..<data.count{
                let value: String = data[i]
                var outVal: UInt64 = 0
                let scanner: Scanner = Scanner.init(string: value)
                scanner.scanHexInt64(&outVal)
                let valueToWrite = UInt16(outVal & 0xffff)
                commandPacket[bitPosition] = UInt8(valueToWrite & 0xff)
                bitPosition += 1
            }
            break
        default:
            break
        }
        let checksum = self.checksum(commandPacket: commandPacket, size: bitPosition)
        
        commandPacket[bitPosition] = UInt8(checksum & 0x00ff)
        bitPosition += 1
        commandPacket[bitPosition] = UInt8(checksum >> 8)
        bitPosition += 1
        commandPacket[bitPosition] = UInt8(CyBLEOtaCommand.cmdEndByte)
        bitPosition += 1
        
        //write
        return Data.init(bytes: commandPacket)
    }

    static func parse(from data: Data?)->CyBLEOtaCommand?{
        guard let data = data, data.count > 1 else{
            return nil
        }
        
        var errorCode = String.init(format: "0x%2x", data[1])
        errorCode = errorCode.replacingOccurrences(of: " ", with: "0")
        
        if errorCode == "0x00"{
            return CyBLEOtaCommand.SUCCESS
        }else{
            return CyBLEOtaCommand.FAILED
        }
    }
    
    static func parse(from this:CyBLEOtaCommand)->Data{
         return this.createCommandPacket()
    }
}

enum CyOtaCommandsChecksumType{
    case crc16
    case checksum
    case null
}
enum CyOtaService: String,Hashable,BLEServices{
    case bootLoader = "00060000-f8ce-11e4-abf4-0002a5d5c51b"
    var uuidString:String{
        return self.rawValue
    }
    static var services: [CBUUID] = {
        return [CBUUID.init(string: CyOtaService.bootLoader.rawValue)]
    }()
}
enum CyCharacteristicBootLoader:String{
    case enable = "00060001-F8CE-11E4-ABF4-0002A5D5C51B"
}

public struct BLEModelOTABotloaderResponse{
    var siliconID:String
    var siliconREV:String
    
    init?(characteristic:IsBLECharacteristic){
        
        guard let data = characteristic.data else{
            return nil
        }
        let pos = 4
        
        var siliconIDstring = String.init()
        
        for n in (0...3).reversed(){
          siliconIDstring = siliconIDstring.appendingFormat("%02x", UInt(data[pos + n]))
        }
        self.siliconID = siliconIDstring
        self.siliconREV = String.init().appendingFormat("%02x", data[pos + 4])
    }
}

public struct BLEModelOTAFashSizeResponse{
    var startRowNumber: UInt16
    var endRowNumber: UInt16
    init(characteristic: IsBLECharacteristic){
        var data = characteristic.data
        self.startRowNumber = CFSwapInt16LittleToHost(UInt16(data![4]))
        self.endRowNumber = CFSwapInt16LittleToHost(UInt16(data![6]))
    }
}

public protocol IsBLECharacteristic:class{
    var uuidString: String{get}
    var data: Data?{get}
    var isWritable:Bool{get}
    var isWritableWithoutResponse:Bool{get}
    var isReadable:Bool{get}
    var isNotifiable:Bool{get}
    var isIndicable: Bool{get}
    var isIndicateEncryptionRequired: Bool{get}
    var isBroadcastable: Bool{get}
    var isExtendedInProperties: Bool{get}
    var isPermitedSignedWrites: Bool{get}
    var isNotifying: Bool{get}
}
extension CBCharacteristic: IsBLECharacteristic{
    
    public var uuidString:String{
        return self.uuid.uuidString
    }
    
    public var data:Data?{
        return self.value
    }
    
    public var isWritable:Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.write.rawValue) != 0
    }
    public var isWritableWithoutResponse:Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.writeWithoutResponse.rawValue) != 0
    }
    
    public var isReadable:Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.read.rawValue) != 0
    }
    
    public var isNotifiable:Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.notify.rawValue) != 0
    }
    
    public var isIndicable: Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.indicate.rawValue) != 0
    }
    
    public var isIndicateEncryptionRequired: Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.indicateEncryptionRequired.rawValue) != 0
    }
    
    public var isBroadcastable: Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.broadcast.rawValue) != 0
    }
    
    public var isExtendedInProperties: Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.extendedProperties.rawValue) != 0
    }
    
    public var isPermitedSignedWrites: Bool{
        return (self.properties.rawValue & CBCharacteristicProperties.authenticatedSignedWrites.rawValue) != 0
    }
}

infix operator >>>> : BitwiseShiftPrecedence

func >>>> (lhs: Int32, rhs: Int32) -> Int32 {
    if lhs >= 0 {
        return lhs >> rhs
    } else {
        return (Int32.max + lhs + 1) >> rhs | (1 << (31-rhs))
    }
}

extension Set where Element == CyBLEOtaCommand.CommandData{
    fileprivate var getFlashArrayID: UInt8?{
        for case let CyBLEOtaCommand.CommandData.flashArrayID(value) in self{
            return value
        }
        return nil
    }
    
    fileprivate var getFlashRowNumber: (UInt16)?{
        for case let CyBLEOtaCommand.CommandData.flashRowNumber(value) in self{
            return value
        }
        return nil
    }
    
    fileprivate var getRowData:Array<String>?{
        for case let CyBLEOtaCommand.CommandData.rowData(value) in self{
            return value
        }
        return nil
    }
}
