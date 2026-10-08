"""Static checks only. Run real builds and Live Photo tests on macOS with Xcode."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
source = (root/'VideoToLivePhoto/VideoToLivePhotoApp.swift').read_text()
project = (root/'VideoToLivePhoto.xcodeproj/project.pbxproj').read_text()
assert 'NSPhotoLibraryAddUsageDescription' in project
assert 'NSPhotoLibraryUsageDescription' not in project
assert 'requestAuthorization(for: .addOnly)' in source
assert 'configuration.selectionLimit = 10' in source
assert 'kCGImagePropertyMakerAppleDictionary as String: ["17": identifier]' in source
assert 'com.apple.quicktime.content.identifier' in source
assert 'com.apple.quicktime.still-image-time' in source
assert 'AVAssetWriterInputMetadataAdaptor' in source
assert 'kCMMetadataBaseDataType_SInt8' in source
assert 'request.addResource(with: .pairedVideo' in source
assert 'PHLivePhoto.request(withResourceFileURLs:' in source
assert not re.search(r'URLSession|https?://|PHAsset.fetch|for: \.readWrite', source)
assert not re.search(r'XCRemoteSwiftPackageReference|SystemCapabilities|CODE_SIGN_ENTITLEMENTS', project)
# Every object reference exists; detect duplicate IDs and broken scheme target references.
object_ids = re.findall(r'^\t\t([A-F0-9]{24}) = \{', project, re.M)
assert len(object_ids) == len(set(object_ids)), 'Duplicate project object ID'
referenced = set(re.findall(r'\b[A-F0-9]{24}\b', project))
assert referenced == set(object_ids), f'Dangling references: {referenced-set(object_ids)}'
scheme = ET.parse(root/'VideoToLivePhoto.xcodeproj/xcshareddata/xcschemes/VideoToLivePhoto.xcscheme')
for node in scheme.findall('.//BuildableReference'):
    assert node.attrib['BlueprintIdentifier'] in referenced
for name in ('VideoToLivePhoto/VideoToLivePhotoApp.swift', 'VideoToLivePhotoTests/LivePhotoIntegrationTests.swift'):
    assert (root/name).is_file()
print('PASS: project references, shared scheme, pairing primitives and privacy constraints.')
print('Apple SDK compilation, XCTest and iPhone LIVE playback still require Xcode / a real device.')
