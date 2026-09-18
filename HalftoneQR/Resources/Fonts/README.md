# Fonts

Drop the SN Pro files here:

    SNPro-Regular.otf
    SNPro-Medium.otf
    SNPro-Semibold.otf
    SNPro-Bold.otf

Nothing else is needed. The app registers every font file it finds in its bundle
at launch (`AppFont.registerBundledFonts`), and `AppFont.sn(_:weight:)` switches
from the system face to SN Pro automatically once the PostScript names resolve.

Until then every call falls back to the system face at the same size, weight and
tracking, so layout does not shift when the files arrive.
