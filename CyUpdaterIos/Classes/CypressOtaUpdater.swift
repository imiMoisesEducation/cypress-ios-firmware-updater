//
//  CyOTAUpdater.swift
//
//  Coded by Moises Lozada.  on 24/4/18.

import Foundation

final public class CyOtaUpdater{
    public var cyacdFiles: [CyacdFile]
    public var manager: CyBLEOTAManager
    internal var checksumType: CyOtaCommandsChecksumType!
    internal var response: BLEModelOTAFashSizeResponse? = nil
    internal var currentFileIndex: Int = 0
    internal let maxDataSize = 133
    internal var currentIndex = 0
    internal var currentRowNumber = 0
    internal var currentArrayID:UInt8 = 0
    internal var currentRowDataArray:[String] = []
    public var currentProgress: (Double,Bool,Error?)->() = {_,_,_ in}
    
    internal let domain = "OTA_UPDATER"
    internal let errorDictionary: [Int:[String:Any]] =
        [ 0: [NSLocalizedDescriptionKey:"ENTER_BOTLOADER characteristic response parser had an error"],
        1:[NSLocalizedDescriptionKey:"Files are empty"] ]
    
    public init(cyacdFileURLs: [URL?], manager: CyBLEOTAManager) throws{
        self.cyacdFiles = try cyacdFileURLs.compactMap({ url throws -> CyacdFile? in
            guard let url = url else{ return nil }
            return try CyacdFile.init(filePath: url)
        })
        
        guard self.cyacdFiles.count > 0 else{
            throw NSError.init(domain: domain, code: 1, userInfo: errorDictionary[1])
        }
        
        self.manager = manager
        self.manager.delegate = self
    }
    
    internal func clean(){
        currentIndex = 0
        currentRowNumber = 0
        currentArrayID = 0
        currentRowDataArray = []
    }
    
    func startUpdate(){
        self.clean()
        
        if Int.init(self.cyacdFiles[currentFileIndex].headers.checksumType) != 0{
            checksumType = .crc16
        }else{
            checksumType = .checksum
        }
        manager.execute(command: CyBLEOtaCommand.ENTER_BOOTLOADER(cs: self.checksumType))
    }
    
    internal func writeCurrentRowDataArray(on otaManager: CyBLEOTAManager){
        let index = currentIndex
        let rowData = self.cyacdFiles[currentFileIndex].rowData[index]
        if currentRowDataArray.count > self.maxDataSize{
            let bIndex = currentRowDataArray.startIndex
            let firstLimit = currentRowDataArray.index(bIndex, offsetBy: self.maxDataSize)
            let dataArray = Array<String>.init(currentRowDataArray[bIndex..<firstLimit])
            currentRowDataArray.removeFirst(self.maxDataSize)
            otaManager.execute(command: CyBLEOtaCommand.SEND_DATA(cs: self.checksumType, data: [.rowData(dataArray)]))
        }else{
            otaManager.execute(command: CyBLEOtaCommand.PROGRAM_ROW(cs: self.checksumType, data: [.flashArrayID(rowData.arrayId),.flashRowNumber(rowData.rowNumber),.rowData(currentRowDataArray)],size:UInt8(currentRowDataArray.count)))
        }
    }
    
    internal func writeFirmwareData(on otaManager: CyBLEOTAManager){
        let index = self.currentIndex
        let rowData = self.cyacdFiles[currentFileIndex].rowData[index]
        if !(rowData.arrayId == self.currentArrayID){
            defer {otaManager.execute(command: CyBLEOtaCommand.GET_FLASH_SIZE(cs: self.checksumType, data: [.flashArrayID(rowData.arrayId)]))}
            self.currentArrayID = rowData.arrayId
            return
        }
        guard let currentRowNumber = Int.init(exactly: rowData.rowNumber % 256),let response = self.response else{
            return
        }
        if currentRowNumber >= response.startRowNumber && currentRowNumber <= response.endRowNumber{
            self.currentRowDataArray = (rowData.dataArray)
            self.writeCurrentRowDataArray(on: otaManager)
        }
    }
}

extension CyOtaUpdater: CyBLEOTAManagerDelegate{
    
    func cyBLEOtaManager(manager: CyBLEOTAManager,notification:CyBLEOTAManagerNotification){
        switch notification {
        case let .enterBootloader(response: packet):
            guard packet.siliconID == self.cyacdFiles[self.currentFileIndex].headers.siliconId && packet.siliconREV == self.cyacdFiles[self.currentFileIndex].headers.siliconRev else{
                let errorNo = 0
                self.currentProgress(0.0,false,NSError.init(domain: self.domain , code: errorNo, userInfo: self.errorDictionary[errorNo] ?? [:]))
                return
            }
            let rowData = self.cyacdFiles[currentFileIndex].rowData[self.currentIndex]
            self.currentArrayID = rowData.arrayId
            manager.execute(
                command:
                CyBLEOtaCommand.GET_FLASH_SIZE(cs: self.checksumType,data: [.flashArrayID(rowData.arrayId)])
            )
        case let .getFlashSize(response: packet):
            self.response = packet
            self.writeFirmwareData(on: manager)
        case let .sendData(suceeded: succeeded):
            guard succeeded else{print("It didnt succeed, idk why");return}
            self.writeCurrentRowDataArray(on: manager)
        case let .programRow(suceeded: succeeded):
            guard succeeded else{print("It didnt succeed, idk why");return}
            let rowData = self.cyacdFiles[self.currentFileIndex].rowData[self.currentIndex]
            self.currentArrayID = rowData.arrayId
            manager.execute(
                command: CyBLEOtaCommand.VERIFY_ROW(cs: self.checksumType, data: [.flashArrayID(rowData.arrayId), .flashRowNumber(rowData.rowNumber)])
            )
            break
        case let .verifyRow(checksum: checksum):
            let rowData = self.cyacdFiles[self.currentFileIndex].rowData[self.currentIndex]
            self.currentArrayID = rowData.arrayId
            
            let rowCheckSum:UInt8 = UInt8(getIntegerFromHex(string: rowData.checksumOTA) & 0xff)
            let arrayID:UInt8 = rowData.arrayId
            let rownumber:UInt16 = UInt16(rowData.rowNumber & 0xffff)
            let dataLength:UInt16 = UInt16(rowData.dataLenght & 0xffff)
            let sum: UInt8 = rowCheckSum &+ arrayID &+ UInt8(rownumber & 0xff) &+ UInt8(rownumber >> 8) &+ UInt8(dataLength & 0xff) &+ UInt8(dataLength >> 8)
            
            guard sum == checksum else{print("checksum missmatch"); return}
            
            self.currentIndex += 1
            self.currentProgress(Double(currentIndex)/Double(self.cyacdFiles[self.currentFileIndex].rowData.count),false,nil)
            if self.currentIndex < self.cyacdFiles[self.currentFileIndex].rowData.count{ self.writeFirmwareData(on: manager) }
            else{
                manager.execute(
                    command:
                    CyBLEOtaCommand.VERIFY_CHECKSUM(cs: self.checksumType)
                )
            }
        case let .verifyChecksum(succeeded: suceeded):
            guard suceeded else {
                let errNo = 10
                self.currentProgress(0.0,false,NSError.init(domain: self.domain, code: errNo, userInfo: self.errorDictionary[errNo] ?? [:]))
                return
            }
            self.currentProgress(1,false,nil)
            
            self.currentFileIndex += 1
            if self.currentFileIndex == self.cyacdFiles.count{
                manager.execute(
                    command:
                    CyBLEOtaCommand.EXIT_BOOTLOADER(cs: self.checksumType)
                )
            }else{
                self.startUpdate()
            }
        case .exitBootloader:
            self.currentProgress(1,true,nil)
        default:
            return
        }
    }
}
