# Final Cut Pro export

GeMotion exports Final Cut Pro timelines using **FCPXML 1.14**. Apple introduced
this version in Final Cut Pro 12.0 and still lists it as the current interchange
format for the Final Cut Pro 12.x line. FCPXML 1.10 was the first version that
supported the `.fcpxmld` bundle format, but it is no longer the current version.

The download is a ZIP archive because web browsers cannot download a directory
bundle directly. To open the project:

1. Download and unzip `final_cut_pro_<video-id>.zip`.
2. Open the contained `GeMotion-<video-id>.fcpxmld` bundle in Final Cut Pro.

The bundle contains `Info.fcpxml` and a `Media` directory. The timeline uses
relative media URLs, so keep the bundle intact when moving it to another Mac.
Each generated video segment is represented as a separate timeline clip. The
internal MPEG transport-stream segments are losslessly remuxed to MOV containers
before export, which avoids another video encode and uses a container supported
natively by Final Cut Pro.

References:

- [Importing FCPXML Data](https://developer.apple.com/documentation/professional-video-applications/importing-fcpxml-data)
- [FCPXML Bundle Reference](https://developer.apple.com/documentation/professional-video-applications/fcpxml-bundle-reference)
- [FCPXML media-rep](https://developer.apple.com/documentation/professional-video-applications/media-rep)
- [Final Cut Pro release notes](https://support.apple.com/en-us/102825)
- [Media formats supported in Final Cut Pro](https://support.apple.com/guide/final-cut-pro/supported-media-formats-ver2833f855/mac)
