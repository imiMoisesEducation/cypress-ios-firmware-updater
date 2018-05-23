//
//  CyacdFile.swift
//
//  Coded by Moises Lozada.  on 20/4/18.

import Foundation

/// Is able to parse Cyadcd files, format used when updating a new firmware on Cy Devices
public final class CyacdFile{
    
    public var headers: CyacdHeaders
    public var rowIds: Array<CyacdRowID>
    public var rowData: Array<CyacdRowData>
    
    
    /// Initialize the file with its separated components
    public init(headers:CyacdHeaders,rowIds:Array<CyacdRowID>,rowData:Array<CyacdRowData>) {
        self.headers = headers
        self.rowIds = rowIds
        self.rowData = rowData
    }
    
    
    /// Parse the file directly from a local file url
    ///
    /// - Parameter filePath: Path to the local file
    /// - Throws: A `ErrorCyacdFile` if anyhting goes wrong
    public init(filePath: URL) throws{
        
        
        //Extracts the file's content into a string
        let fileContents = try String.init(contentsOf: filePath, encoding: .utf8)
        
        //If empty. throw an error
        guard !fileContents.isEmpty else{
            throw ErrorCyacdFile.fileEmpty
        }
        
        //Get a `String` for each new line in `fileConstents`'s content and remove junk data
        var fileContentsArray = fileContents.components(separatedBy: .newlines)
        CyacdFile.removeEmptyRowsAndJunkData(from: &fileContentsArray)
        
        
        //The first line are always the headers, parse them, and throwm an error if neede
        let fileHeader: String = fileContentsArray[0]
        guard fileHeader.lengthOfBytes(using: .utf8) >= constants.FILE_HEADER_MAX_LENGTH else{
            throw ErrorCyacdFile.fileFormatInvalidFile
        }
        self.headers = CyacdHeaders.init(fileHeader: fileHeader)
        fileContentsArray.remove(at: 0) //Remove the already used data
        
        var rowId = ""
        var rowCount = 0
        self.rowIds = []
        self.rowData = []
        // Parse the rest of the file
        try fileContentsArray.forEach {[unowned self] (dataRowString) throws in
            guard dataRowString.lengthOfBytes(using: .utf8) > 20 else{
                throw ErrorCyacdFile.fileFormatDataFormat
            }
            
            guard let cyacdRowData = CyacdRowData.init(rowData: dataRowString) else{
                throw ErrorCyacdFile.parsingInvalidFile
            }
            
            self.rowData.append(cyacdRowData)
            let tBeginIndex = dataRowString.startIndex
            let tEndIndex = dataRowString.index(tBeginIndex, offsetBy: 2)
            let currentIndexInLine = String(dataRowString[tBeginIndex..<tEndIndex])
            if rowId.isEmpty { // The first loop
                rowId = currentIndexInLine
                rowCount = rowCount + 1
            }else if rowId ==  currentIndexInLine{ // data belongs to the same rowId
                rowCount = rowCount + 1
            }else{ // rowID changed
                self.rowIds.append(CyacdRowID.init(rowID: rowId, rowCount: rowCount))
                rowId = currentIndexInLine
                rowCount = 1
            }
        }
        self.rowIds.append(CyacdRowID.init(rowID: rowId, rowCount: rowCount))
    }
    

    /// Removes all the non-alphanumeric values from a string
    ///
    /// - Parameter array: Array to clean
    internal static func removeEmptyRowsAndJunkData(from array: inout [String]){
        for n in (0..<array.count).reversed(){
            if array[n] == ""{
                array.remove(at: n)
            }else{
                let charactersToRemove = CharacterSet.alphanumerics.inverted
                let trimmedReplacement = array[n].components(separatedBy: charactersToRemove).joined(separator: "")
                array[n] = trimmedReplacement
            }
        }
    }
    internal struct constants{
        static let FILE_HEADER_MAX_LENGTH = 12
    }
}

public struct CyacdHeaders{
    public var siliconId: String = ""
    public var siliconRev:String = ""
    public var checksumType:String = ""
    
    /// Parses a string to a header file
    ///
    /// - Parameter fileHeader: `String` value, from the header line of the file
    fileprivate init(fileHeader: String){
        let bIndex = fileHeader.startIndex
        let firstLimit = fileHeader.index(bIndex, offsetBy: 8)
        let secondLimit = fileHeader.index(firstLimit, offsetBy: 2)
        let thirdLimit = fileHeader.index(secondLimit, offsetBy: 2)
        self.siliconId = String(fileHeader[bIndex..<firstLimit]).lowercased()
        self.siliconRev = String(fileHeader[firstLimit..<secondLimit]).lowercased()
        self.checksumType = String(fileHeader[secondLimit..<thirdLimit]).lowercased()
    }
}

extension CyacdHeaders: Equatable{
    public static func ==(lhs:CyacdHeaders,rhs:CyacdHeaders)->Bool{
        if lhs.siliconRev == rhs.siliconRev && lhs.checksumType == rhs.checksumType && lhs.siliconId == rhs.siliconId{
            return true
        }
        return false
    }
}


/// Row id of the Cyacd file
public struct CyacdRowID{
    public var rowID: String
    public var rowCount: Int
    fileprivate init(rowID: String, rowCount: Int){
        self.rowID = rowID
        self.rowCount = rowCount
    }
}


/// One row of data whithin the CyadFile
public struct CyacdRowData{
    public var arrayId: UInt8 = 0
    public var rowNumber: UInt16 = 0
    public var dataLenght: UInt64 = 0
    public var dataArray: [String] = []
    public var checksumOTA: String = ""
    public var base64Array: String = ""
    
    
    /// Parses the row of data properly
    ///
    /// - Parameter rowData: row of data taken from the cyacd file
    fileprivate init?(rowData: String){
        let bIndex = rowData.startIndex
        let firstLimit = rowData.index(bIndex, offsetBy: 2)
        let secondLimit = rowData.index(firstLimit,offsetBy: 4)
        let thirdLimit =  rowData.index(secondLimit, offsetBy: 4)
        let lastLimit = rowData.index(thirdLimit,offsetBy: rowData.lengthOfBytes(using: .utf8) - 12)
        
        self.arrayId = UInt8(String(rowData[bIndex..<firstLimit]))!
        self.rowNumber = UInt16.init(truncating: NSNumber.init(value: getIntegerFromHex(string: String(rowData[firstLimit..<secondLimit]))))
        
        self.dataLenght = getIntegerFromHex(string: String(rowData[secondLimit..<thirdLimit]))
        let dataString = String(rowData[thirdLimit..<lastLimit])
        
        guard self.dataLenght == dataString.lengthOfBytes(using: .utf8)/2 else{
            return nil
        }
        
        var byteArray = [String]()
        
        var i = 0
        var bDataIndex = dataString.startIndex
        var eDataIndex = dataString.index(bDataIndex, offsetBy: 2)
        while(i+2 <= dataString.lengthOfBytes(using: .utf8)){
            byteArray.append(String(dataString[bDataIndex..<eDataIndex]))
            i = i + 2
            bDataIndex = dataString.index(bDataIndex, offsetBy: 2)
            
            if bDataIndex == dataString.endIndex{
                continue
            }
   
            eDataIndex = dataString.index(eDataIndex, offsetBy: 2)
        }
        let endIndex = rowData.endIndex
        let offset = rowData.index(endIndex, offsetBy: -2)
        self.dataArray = byteArray
        self.checksumOTA = String(rowData[offset..<endIndex])
    }
}

extension CyacdRowData: Equatable{
    internal func getBytesFromHex()->[UInt8]{
        return dataArray.map { (str) -> UInt8 in
            let scanner: Scanner = Scanner.init(string: "0x\(str)")
            var int32: UInt32 = 0
            scanner.scanHexInt32(&int32)
            return UInt8(int32 & 0xff)
        }
    }
    
    static public func ==(lhs: CyacdRowData,rhs:CyacdRowData) -> Bool{
        
        guard lhs.arrayId == lhs.arrayId &&
            lhs.dataLenght == lhs.dataLenght &&
            lhs.checksumOTA == lhs.checksumOTA else{ return false }
        
        if lhs.base64Array != "" && rhs.base64Array == ""{
            let base64 = Data.init(bytes: rhs.getBytesFromHex()).base64EncodedString()
            return lhs.base64Array == base64
        }else if rhs.base64Array != "" && lhs.base64Array == ""{
            let base64 = Data.init(bytes: lhs.getBytesFromHex()).base64EncodedString()
            return rhs.base64Array == base64
        }else if rhs.base64Array == "" && lhs.base64Array == ""{
            return rhs.dataArray == lhs.dataArray
        }else{
            return rhs.base64Array == lhs.base64Array
        }
    }
}


/// Errors related to the Cyacd parsing parsing
public enum ErrorCyacdFile:Error{
    case parsingInvalidFile
    case fileFormatDataFormat
    case fileFormatInvalidFile
    case fileEmpty
    var localizedDescription: String{
        get{
            switch self {
            case .parsingInvalidFile:
                return "Parsing, invalid or corrupt file.(CyadcdFile)"
            case .fileFormatDataFormat:
                return "File format, The firmware file data format is invalid! Parsing failed.(CyadcdFile)"
            case .fileFormatInvalidFile:
                return "File format, invalid or corrupt file.(CyadcdFile)"
            case .fileEmpty:
                return "The firmware file is empty!.(CyadcdFile)"
            }
        }
    }
}

internal func getIntegerFromHex(string: String) -> UInt64{
    var integerValue: UInt64 = 0
    let scanner = Scanner.init(string: string)
    scanner.scanHexInt64(&integerValue)
    return integerValue;
}
