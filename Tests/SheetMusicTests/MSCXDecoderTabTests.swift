import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMSCX
@testable import SheetMusicXMLTools
import Testing

/// Decode-side coverage for the tablature additions: `<fret>` /
/// `<string>` on notes, `<StaffType group="tablature">` properties,
/// `<StringData>` tunings, and `<linkedTo>` staff links.
struct MSCXDecoderTabTests {
    private func parseNote(_ xml: String) throws -> Note {
        let node = try XMLTreeParser.parse(Data(xml.utf8))
        return try Note.decode(node)
    }

    private func parseStaffDeclaration(
        _ xml: String,
    ) throws -> (mscxID: String?, linkedToID: String?, staff: Staff) {
        let node = try XMLTreeParser.parse(Data(xml.utf8))
        return Staff.declared(node)
    }

    // MARK: - Note <fret>/<string>

    @Test func fretAndStringDecode() throws {
        let xml = "<Note><pitch>64</pitch><tpc>18</tpc><fret>5</fret><string>1</string></Note>"
        let note = try parseNote(xml)
        #expect(note.fret == 5)
        #expect(note.string == 1)
    }

    @Test func openStringFretZeroDecodes() throws {
        let xml = "<Note><pitch>40</pitch><tpc>18</tpc><fret>0</fret><string>5</string></Note>"
        let note = try parseNote(xml)
        #expect(note.fret == 0)
        #expect(note.string == 5)
    }

    @Test func absentFretAndStringStayNil() throws {
        let note = try parseNote("<Note><pitch>60</pitch><tpc>14</tpc></Note>")
        #expect(note.fret == nil)
        #expect(note.string == nil)
    }

    @Test func malformedFretWarnsAndDropsBoth() throws {
        let collector = MSCXDiagnosticCollector()
        let xml = "<Note><pitch>64</pitch><tpc>18</tpc><fret>x</fret><string>1</string></Note>"
        let note = try MSCXParserContext.$collector.withValue(collector) {
            try parseNote(xml)
        }
        #expect(collector.entries.contains { $0.code == "mscx.note.invalidFret" })
        #expect(note.fret == nil)
        #expect(note.string == nil)
        #expect(note.pitch == 64) // pitch survives — structural truth
    }

    @Test func negativeStringWarnsAndDropsBoth() throws {
        let collector = MSCXDiagnosticCollector()
        let xml = "<Note><pitch>64</pitch><tpc>18</tpc><fret>3</fret><string>-1</string></Note>"
        let note = try MSCXParserContext.$collector.withValue(collector) {
            try parseNote(xml)
        }
        #expect(collector.entries.contains { $0.code == "mscx.note.invalidFret" })
        #expect(note.fret == nil)
        #expect(note.string == nil)
    }

    // MARK: - <StaffType group="tablature">

    @Test func tabCommonStaffTypeDecodes() throws {
        // The exact property set MuseScore writes for tab6StrCommon.
        let xml = """
        <Staff id="2">
          <StaffType group="tablature">
            <name>tab6StrCommon</name>
            <lines>6</lines>
            <lineDistance>1.5</lineDistance>
            <durations>0</durations>
            <durationFontName>MuseScore Tab Modern</durationFontName>
            <durationFontSize>15</durationFontSize>
            <durationFontY>0</durationFontY>
            <fretFontName>MuseScore Tab Sans</fretFontName>
            <fretFontSize>9</fretFontSize>
            <fretFontY>0</fretFontY>
            <linesThrough>0</linesThrough>
            <minimStyle>1</minimStyle>
            <onLines>1</onLines>
            <showRests>1</showRests>
            <stemsDown>1</stemsDown>
            <stemsThrough>0</stemsThrough>
            <upsideDown>0</upsideDown>
            <showTabFingering>1</showTabFingering>
            <useNumbers>1</useNumbers>
          </StaffType>
        </Staff>
        """
        let decl = try parseStaffDeclaration(xml)
        let staff = decl.staff
        #expect(staff.staffType == "tab6StrCommon")
        #expect(staff.group == "tablature")
        #expect(staff.isTablature)
        let props = staff.typeProperties
        #expect(props.lines == 6)
        #expect(props.lineDistanceSp == 1.5)
        #expect(props.genKeysig == false) // forced off for tablature
        #expect(props.genTimesig == true)
        #expect(props.stemless == false)
        let tab = try #require(props.tab)
        #expect(tab.minimStyle == .shorter)
        #expect(tab.onLines == true)
        #expect(tab.showRests == true)
        #expect(tab.stemsDown == true)
        #expect(tab.stemsThrough == false)
        #expect(tab.useNumbers == true)
        #expect(tab.showBackTied == true) // derived: !stemless
        #expect(tab.fretFontSize == 9)
        #expect(tab.fretFontName == "MuseScore Tab Sans")
    }

    @Test func tabSimpleStaffTypeDecodes() throws {
        // Simple preset: stemless, no timesig, no rests; MuseScore
        // derives showBackTied = !stemless when the element is absent.
        let xml = """
        <Staff id="2">
          <StaffType group="tablature">
            <name>tab6StrSimple</name>
            <lines>6</lines>
            <lineDistance>1.5</lineDistance>
            <stemless>1</stemless>
            <timesig>0</timesig>
            <minimStyle>0</minimStyle>
            <showRests>0</showRests>
          </StaffType>
        </Staff>
        """
        let props = try parseStaffDeclaration(xml).staff.typeProperties
        #expect(props.stemless == true)
        #expect(props.genTimesig == false)
        let tab = try #require(props.tab)
        #expect(tab.minimStyle == TabStaffStyle.MinimStyle.none)
        #expect(tab.showRests == false)
        #expect(tab.showBackTied == false) // derived from stemless
    }

    @Test func explicitShowBackTiedWinsOverStemlessDerivation() throws {
        // <showBackTied> after <stemless> must override the compat
        // derivation regardless of order sensitivity.
        let xml = """
        <Staff id="2">
          <StaffType group="tablature">
            <name>custom</name>
            <stemless>1</stemless>
            <showBackTied>1</showBackTied>
          </StaffType>
        </Staff>
        """
        let props = try parseStaffDeclaration(xml).staff.typeProperties
        #expect(props.stemless == true)
        #expect(props.tab?.showBackTied == true)
    }

    @Test func legacySlashStyleAliasSetsStemless() throws {
        let xml = """
        <Staff id="2">
          <StaffType group="tablature">
            <name>legacy</name>
            <slashStyle>1</slashStyle>
          </StaffType>
        </Staff>
        """
        let props = try parseStaffDeclaration(xml).staff.typeProperties
        #expect(props.stemless == true)
        #expect(props.tab?.showBackTied == false)
    }

    @Test func standardStaffTypeKeepsDefaults() throws {
        let xml = """
        <Staff id="1">
          <StaffType group="pitched"><name>stdNormal</name></StaffType>
        </Staff>
        """
        let props = try parseStaffDeclaration(xml).staff.typeProperties
        #expect(props == StaffTypeProperties())
        #expect(props.tab == nil)
    }

    @Test func unknownTabPropertyWarns() throws {
        let collector = MSCXDiagnosticCollector()
        let xml = """
        <Staff id="2">
          <StaffType group="tablature">
            <name>tab6StrCommon</name>
            <mysteryKnob>7</mysteryKnob>
          </StaffType>
        </Staff>
        """
        _ = try MSCXParserContext.$collector.withValue(collector) {
            try parseStaffDeclaration(xml)
        }
        #expect(collector.entries.contains {
            $0.code == "mscx.staffType.unsupportedTabProperty"
        })
    }

    @Test func unknownPropertyOnStandardStaffStaysSilent() throws {
        let collector = MSCXDiagnosticCollector()
        let xml = """
        <Staff id="1">
          <StaffType group="pitched">
            <name>stdNormal</name>
            <mysteryKnob>7</mysteryKnob>
          </StaffType>
        </Staff>
        """
        _ = try MSCXParserContext.$collector.withValue(collector) {
            try parseStaffDeclaration(xml)
        }
        #expect(collector.entries.isEmpty)
    }

    // MARK: - <StringData>

    @Test func stringDataDecodesGuitarTuning() throws {
        let xml = """
        <Instrument id="guitar">
          <StringData>
            <frets>19</frets>
            <string>40</string>
            <string>45</string>
            <string>50</string>
            <string>55</string>
            <string>59</string>
            <string>64</string>
          </StringData>
          <Channel><program value="24"/></Channel>
        </Instrument>
        """
        let node = try XMLTreeParser.parse(Data(xml.utf8))
        let instrument = try Instrument.decode(node)
        let sd = try #require(instrument.stringData)
        #expect(sd.frets == 19)
        #expect(sd.strings.map(\.pitch) == [40, 45, 50, 55, 59, 64])
        #expect(sd.strings.allSatisfy { !$0.open })
    }

    @Test func stringDataOpenAttributeDecodes() throws {
        let xml = """
        <Instrument id="banjo">
          <StringData>
            <frets>22</frets>
            <string open="1">67</string>
            <string>50</string>
          </StringData>
          <Channel><program value="105"/></Channel>
        </Instrument>
        """
        let node = try XMLTreeParser.parse(Data(xml.utf8))
        let sd = try #require(try Instrument.decode(node).stringData)
        #expect(sd.strings[0].open == true)
        #expect(sd.strings[1].open == false)
    }

    @Test func absentStringDataStaysNil() throws {
        let xml = "<Instrument id=\"piano\"><Channel><program value=\"0\"/></Channel></Instrument>"
        let node = try XMLTreeParser.parse(Data(xml.utf8))
        #expect(try Instrument.decode(node).stringData == nil)
    }

    // MARK: - <linkedTo>

    @Test func linkedToResolvesToPartRelativeIndex() throws {
        let xml = """
        <Part id="1">
          <Staff id="1">
            <StaffType group="pitched"><name>stdNormal</name></StaffType>
          </Staff>
          <Staff id="2">
            <StaffType group="tablature"><name>tab6StrCommon</name></StaffType>
            <linkedTo>1</linkedTo>
          </Staff>
          <Instrument id="guitar"><Channel><program value="24"/></Channel></Instrument>
        </Part>
        """
        let node = try XMLTreeParser.parse(Data(xml.utf8))
        let pairing = try Part.decodePairing(node, fallbackIndex: 1)
        #expect(pairing.declared[0].staff.linkedToStaffOffset == nil)
        #expect(pairing.declared[1].staff.linkedToStaffOffset == 0)
    }

    @Test func danglingLinkedToIsDropped() throws {
        let xml = """
        <Part id="1">
          <Staff id="2">
            <StaffType group="tablature"><name>tab6StrCommon</name></StaffType>
            <linkedTo>99</linkedTo>
          </Staff>
          <Instrument id="guitar"><Channel><program value="24"/></Channel></Instrument>
        </Part>
        """
        let node = try XMLTreeParser.parse(Data(xml.utf8))
        let pairing = try Part.decodePairing(node, fallbackIndex: 1)
        #expect(pairing.declared[0].staff.linkedToStaffOffset == nil)
    }
}
