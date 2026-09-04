import 'field_namer_stub.dart'
    if (dart.library.js_interop) 'field_namer_web.dart' as impl;

/// When a ticket-form field gains focus, stamp the engine's transparent
/// text-editing element with a stable `id`/`name` (web only). Without them
/// Chrome warns that the field cannot be autofilled; there is no widget API
/// to set the attributes directly. No-op on native platforms.
void nameFocusedFormField(String id, String name) {
  impl.nameFocusedFormField(id, name);
}
