# Attribution

PureXML is an independent Swift implementation.

This project is informed by the behavior and public API surface of established
XML parsers, including [libxml2](https://gitlab.gnome.org/GNOME/libxml2),
[expat](https://github.com/libexpat/libexpat), and Foundation's `XMLParser`, and
by the [W3C XML 1.0 specification](https://www.w3.org/TR/xml/) and its
conformance test suite. Their behavior is a compatibility reference for PureXML.

PureXML does not copy source code from libxml2, expat, Foundation, or any other
XML parser into the public package. The implementation under `Sources/` is
written in Swift for this repository.

Upstream sources remain available from their projects:

- https://gitlab.gnome.org/GNOME/libxml2
- https://github.com/libexpat/libexpat
- https://www.w3.org/TR/xml/

This file is the canonical attribution notice for the project; the `LICENSE`
file is kept to the standard MIT text so it is correctly detected as MIT.

The private `PureXMLResearch` repository contains reference source snapshots and
conformance corpora for study and compatibility research. That repository is not
the implementation source for PureXML.
