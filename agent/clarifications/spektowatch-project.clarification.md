# SpektoWatch Project Clarification

Status: addressed  
Created: 2026-05-11  
Addressed: 2026-05-11  
Source draft: `agent/drafts/spektowatch-project.draft.md`

## How To Respond

Answer on the lines beginning with `>`. Partial answers are fine. You can also
write directives such as "explore the codebase", "recommend an option", or
"this decision has cascading effects".

After responding, invoke `@acp.clarification-address` to process the answers
and update this document with decisions, tradeoffs, and recommendations.

## Addressing Summary

<!-- acp-addressed
Key decisions:
- Position SpektoWatch first as a field engineering tool for audio engineers,
  while keeping the first screen approachable for normal users.
- Compliance claims are allowed only when using a calibrated external
  measurement microphone. Built-in iPhone and Apple Watch microphones should be
  presented as approximate/non-proof measurements.
- The primary user flow is: open app, measure live sound, record, review the
  saved measurement, add analysis widgets, and create a measurement protocol.
- The next implementation focus should be performance stabilization and watch
  architecture. Masking is explicitly out of scope for the next milestone even
  though it remains a polished core feature later.
- Recording must prioritize no dropped frames over battery savings or maximum
  spectral detail when tradeoffs are unavoidable.

Recommended defaults:
- Treat LAeq as the headline metric, using A/Z weighting and Fast time
  weighting for the first complete version.
- Use consumer-friendly labels by default, with engineering terminology
  available through advanced views/settings.
- Support multiple saved dashboard layouts, global settings by default, and
  per-widget overrides.
- Keep recordings fully local by design; location is optional and explicitly
  user-controlled.

Remaining follow-up:
- Confirm exact external microphone/compliance target before implementing any
  standards language.
- Confirm the oldest supported Apple Watch generation; iPhone 12 is defined,
  watch generation is still open.
-->

## 1. Product Positioning

The draft says SpektoWatch should sit between simple dB meters and professional
analysis tools. The exact level of professional rigor is not yet defined.

### Q1.1

Should SpektoWatch position itself as an educational/prosumer acoustic analysis
tool, a field engineering tool, or a measurement-grade professional instrument?

>in first place as field engineering tool but shouldnt overwhelm normal users on first sight. But in a later state i would like to implement usability of external measurement microphones and then it must be an measuremnt tool 

### Q1.2

Does the app need to claim compliance with any formal standards, or should it
avoid compliance claims and present readings as calibrated/estimated app-level measurements?

>yes it does claim compliance but only when used with external microphone because the normal iphone/aw mic is not as precise. 

### Q1.3

What is the primary first-use workflow: open app and inspect current sound,
start a recording, analyze masking, review past measurements, or configure a
custom dashboard?

>OPen, measure live sound, record, view recorded measurement, add nedded analyzing widgets and create a measuremnt protoco

<!-- acp-addressed
Decision: The default product framing is field engineering first, but not
expert-only on first launch. Compliance is a future-capable track that depends
on calibrated external microphone support. The iPhone/AW built-in microphone
path must avoid proof-grade claims.

Implementation implication: onboarding, labels, reports, and export language
must distinguish "approximate built-in microphone measurement" from "calibrated
external microphone measurement". The main workflow should optimize for live
measurement first, then recording review and protocol/report creation.
-->

## 2. Target Users

The draft lists audio engineers, acoustics students, technicians, power users,
and Apple Watch users. These users have different expectations and tolerances. Audio Engineers and power users. all of them could be apple watch useres, this dont describe their needs rather then their input mic and analysing capabilities 

### Q2.1

Which user group should drive the default UX and acceptance criteria for the
next milestone?

>audio engineer

### Q2.2

What level of domain terminology should the UI use by default: consumer-friendly
labels, engineering terminology, or an expert mode with advanced labels?

>consumer-friendly 

<!-- acp-addressed
Decision: Audio engineers are the primary acceptance audience, but the default
UI language should remain consumer-friendly. Advanced acoustic terms can appear
inside detailed widgets, settings, reports, and expert affordances.

Recommendation: Use readable display labels such as "Average level" with
metric notation beside it, for example "LAeq". This avoids overwhelming first
use while preserving technical precision.
-->

## 3. Measurement Model

The app supports FFT, frequency weighting, loudness, peak, and time-weighted
metrics. The draft does not identify which metrics are mandatory, optional, or
primary.

>All are energy over time
### Q3.1

Which live metric is the main headline value: LAF, LAeq, LCpeak, loudness, or a
configurable choice?

>L_a;eq

### Q3.2

Which frequency weightings and time weightings must be supported in the first
complete version of this feature?

>a/z and fast

### Q3.3

Should calibration be treated as a required setup step, an optional advanced
setting, or an automatic device-profile default with manual override?

>optional but needed for compliance claims 

### Q3.4

What accuracy expectations should be communicated to users when using built-in
iPhone or Apple Watch microphones?

>the truth, that measurement is vague and no representational proof

<!-- acp-addressed
Decision: LAeq is the headline live metric. First complete support should
include A and Z frequency weighting and Fast time weighting. Calibration is
optional during normal use but required before any compliance-grade claim.

Correction/normalization: Interpret `L_a;eq` as `LAeq`.

Implementation implication: built-in microphone UI/report copy should clearly
state that readings are approximate and not formal proof. External calibrated
microphones unlock stricter language once the app supports the required
calibration workflow and metadata capture.
-->

## 4. Dashboard Scope

The draft calls for a modular dashboard but does not define the required widget
set or configuration depth.

### Q4.1

Which widgets are required for the first milestone: spectrogram, waterfall,
spectrum, level history, loudness, single-value metrics, tone generator,
masking, recordings, or watch status?

>spectrogram, spectrum, level history,single-value metrics,recordings

### Q4.2

Should users be able to create multiple saved dashboard layouts, or is a single
customizable dashboard enough for now?

>multiple saved layouts 

### Q4.3

Should widget settings inherit global audio settings by default, or should each
widget be independently configurable?

>global in general but every widget should be independently configurable as well 

### Q4.4

Are there any widgets that should be read-only views of engine state rather than
having their own settings?

>i dont think so

<!-- acp-addressed
Decision: Required first dashboard widgets are spectrogram, spectrum, level
history, single-value metrics, and recordings. Multiple saved layouts are
required. Widgets should inherit global audio settings by default while allowing
independent per-widget overrides.

Tradeoff: Multiple layouts increase persistence and UI complexity, but they
match the field workflow where users may want different views for live checks,
recording review, and protocol preparation.
-->

## 5. Recording And Persistence

The draft says recordings should include audio, metadata, notes, photos, and
structured measurement data, but does not define the minimum record.

### Q5.1

What is the minimum useful saved recording: audio only, measurement data only,
audio plus measurement data, or measurement data plus annotations?

>audio plus measurement data. Things like metadata, notes and photos should be addable afterwards 

### Q5.2

Which metadata fields are required at recording creation: name, date, duration,
location, photos, notes, calibration state, microphone source, dashboard state,
or environmental context?

>name, date, duration 

### Q5.3

Should users be able to add markers/events during recording from iPhone, Apple
Watch, or both?

>both 

### Q5.4

How important is backwards compatibility with existing `.spekto` measurement
files during the next iteration?

>very 

<!-- acp-addressed
Decision: A saved recording must include audio plus structured measurement
data. Metadata, notes, and photos can be added after recording. Creation-time
metadata requires name, date, and duration. Markers/events should be addable
from both iPhone and Apple Watch. Backwards compatibility with existing `.spekto`
files is very important.

Implementation implication: avoid breaking `MeasurementDataReader` and existing
file format assumptions. If new fields are needed, add versioned optional
metadata rather than changing the minimum readable frame contract.
-->

## 6. Watch Experience

The draft treats Apple Watch as a companion display or wearable measurement
surface. It does not choose which role to prioritize first.

### Q6.1

Which watch mode should be built first: companion display for iPhone recording,
watch microphone as wearable source, or standalone watch recording?

>watch microphone as wearable source and secondary as standalone watch recording

### Q6.2

Should the watch be allowed to start/stop phone recordings, or should it only
mirror phone state?

>yes the first 

### Q6.3

Which watch-native surfaces matter most: complication, Smart Stack widget,
threshold notification, haptic alert, or standalone recording view?

>complication

### Q6.4

What update rate is acceptable for watch live data, balancing responsiveness,
battery, and WatchConnectivity reliability?

>every second at least 

<!-- acp-addressed
Decision: Prioritize watch microphone as wearable source first, then standalone
watch recording. The watch should be able to start and stop phone recordings.
The first watch-native surface should be a complication. Watch live data must
update at least once per second.

Implementation implication: keep WatchConnectivity payloads compact and typed.
One-second updates are compatible with the existing low-bandwidth direction;
avoid raw audio transfer.
-->

## 7. Masking Workflow

The draft includes tone generation and masking workflows, but the core masking
use case is not fully specified.

### Q7.1

What problem should the masking workflow solve first: trigger acquisition,
masking profile design, playback/noise generation, validation against measured
sound, or reporting?

>trigger acquisition, masking profile design, playback/noise generation

### Q7.2

Should masking profiles be saved as reusable user assets?

>yes

### Q7.3

Should masking generation be considered an experimental tool or a polished core
feature?

>polished core feature 

<!-- acp-addressed
Decision: Masking is intended as a polished core feature eventually. Its first
use cases are trigger acquisition, masking profile design, and playback/noise
generation. Masking profiles should be saved as reusable assets.

Milestone implication: despite being a core feature later, masking is out of
scope for the next milestone per Q11.2. Do not let performance/watch work
expand into masking implementation during the next pass.
-->

## 8. Export And Reporting

The draft references PDF/CSV/report workflows without defining required output.

### Q8.1

Which export format is required first: PDF report, CSV data, raw measurement
file sharing, image export of spectrograms, or all of these?

>all

### Q8.2

What should a PDF report always include: summary metrics, spectrogram, level
history, metadata, photos, notes, calibration info, or method notes?

>summary metrics, levelhistory, metadata, calibration info

### Q8.3

Should exports be designed for technical review, client-facing documentation,
personal logs, or debugging?

>clientäfacing documentation

<!-- acp-addressed
Decision: Export scope is broad: PDF, CSV, raw measurement file sharing, and
spectrogram image export are all desired. PDF reports should always include
summary metrics, level history, metadata, and calibration info. Exports are
client-facing documentation.

Correction/normalization: Interpret `clientäfacing` as `client-facing`.

Recommendation: Because "all export formats" is a large scope, plan this as a
later reporting milestone. The next performance/watch milestone should preserve
existing export behavior but not attempt a full export redesign.
-->

## 9. Performance And Device Support

The draft names performance risks but does not set measurable budgets.

### Q9.1

What is the oldest iPhone and Apple Watch generation that should be supported
for smooth live measurement?

>Iphone 12 

### Q9.2

What are the target live update rates for spectrogram, headline metrics,
dashboard widgets, and watch updates?

>60 fps

### Q9.3

Should measurement recording prioritize no dropped frames, low battery use, or
maximum spectral detail when those goals conflict?

>no dropped frames

<!-- acp-addressed
Decision: iPhone 12 is the oldest defined iPhone performance target. The target
visible update rate is 60 fps. Recording must prioritize no dropped frames.

Recommendation: Treat 60 fps as the UI responsiveness target for live dashboard
surfaces. Watch live data remains at least 1 Hz per Q6.4. For implementation,
make "no dropped measurement frames during recording" the stronger acceptance
criterion than visual frame rate.

Open: Oldest supported Apple Watch generation is still undefined.
-->

## 10. Privacy And Permissions

The app records microphone audio and may store photos, location-like context,
and notes.

### Q10.1

Should location metadata be supported, avoided, or optional with explicit user
control?

>with explicit user control

### Q10.2

Should recordings remain fully local by design, or is cloud/file-provider sync
in scope?

>fully local by design

### Q10.3

What privacy message should users see around microphone, recording, photos, and
possible location metadata?

>i dont know 

<!-- acp-addressed
Decision: Location metadata is optional and requires explicit user control.
Recordings stay fully local by design.

Recommended privacy copy:
"SpektoWatch uses the microphone only while measuring or recording. Recordings,
measurement data, notes, photos, and optional location metadata stay on this
device unless you choose to export or share them. Built-in iPhone and Apple
Watch microphone readings are approximate; calibrated external microphones are
required for compliance-grade measurements."
-->

## 11. Milestone Boundary

The draft contains enough scope for several milestones. The first milestone
needs a sharper boundary.

### Q11.1

What outcome should mark the next milestone as complete?

>i dont know 

### Q11.2

Which feature should explicitly be out of scope for the next milestone, even if
it is important later?

>masking tool

### Q11.3

Should the next milestone focus on user-visible functionality, performance
stabilization, watch architecture, recording review, or ACP planning?

> performance
stabilization, watch architecture

<!-- acp-addressed
Decision: The next milestone should focus on performance stabilization and
watch architecture. The masking tool is explicitly out of scope.

Recommended milestone completion outcome:
"Live iPhone measurement and recording remain smooth on iPhone 12, with no
dropped measurement frames during a representative recording run; the watch
microphone path streams compact processed data at least once per second; existing
recordings and `.spekto` files remain readable; masking code is untouched except
where needed to preserve builds/tests."

This gives the milestone a measurable boundary while honoring the performance
and watch priorities.
-->

## 12. Acceptance Criteria

The draft lists quality requirements, but feature-level acceptance criteria are
not concrete yet.

### Q12.1

What manual acceptance test should a user be able to perform to prove the core
feature works end to end?

>the user should be able hold a real pegelmeter near to iphone which is measuring raughly the same levels

### Q12.2

Which automated tests must pass before the milestone can be considered done?

>i dont know 

### Q12.3

What observable failure would make this feature unacceptable even if it compiles
and basic tests pass?

>low fps, wrong measuring

<!-- acp-addressed
Decision: Manual acceptance should compare SpektoWatch against a real sound
level meter placed near the iPhone and confirm roughly matching levels. Low FPS
and wrong measurements are unacceptable failures.

Recommended automated test set for the next milestone:
- `AudioEngineTests`
- `FFTProcessorTests`
- `FrequencyWeightingTests`
- `MeasurementDataIOTests`
- `WatchConnectivityTests`
- `PerformanceProfilingTests`

If a full simulator suite is too expensive, run the smallest targeted xcodebuild
test set covering these areas and document any skipped tests.
-->
