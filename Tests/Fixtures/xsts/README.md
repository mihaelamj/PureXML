# W3C XML Schema Test Suite (XSTS): vendored archive

`xsts-2007-06-20.tar.gz` is the complete, unmodified W3C XML Schema Test Suite,
2006-11-06 release (14,383 settled cases across roughly 39,399 files), exactly as
published by the W3C.

- Source: <https://www.w3.org/XML/2004/xml-schema-test-suite/xmlschema2006-11-06/xsts-2007-06-20.tar.gz>
- SHA-256: `902176b25e4111cf96b08663107521a4992e8ea67aad6b815592a6a5b4b9ea06`
- Size: 4,367,182 bytes

## License

The suite is published under the W3C Document License, which permits
redistribution only as the complete, unmodified archive. This file is that
archive, byte for byte, kept in its original `.tar.gz` form for that reason.

Do not commit the extracted files. Extracting them and committing the loose
files is a modified redistribution and is not permitted by the license. Keep the
archive sealed; extract it locally instead (see below).

## Use

Extract it to the path the conformance runner expects, then point `XSTS_ROOT` at
the result:

    bash scripts/fetch-xsts.sh
    export XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06
    XSTS_ROOT=$XSTS_ROOT swift test -c release --filter XSTSSuiteTests

`scripts/fetch-xsts.sh` extracts this vendored archive when it is present (no
network needed) and falls back to downloading it from the W3C otherwise.
