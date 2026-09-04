import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Gives the Flutter web engine's transparent text-editing element a stable
/// `id`/`name` so Chrome does not flag the field as unautofillable.
///
/// The engine creates one <input>/<textarea> (class `flt-text-editing`) per
/// focused TextField, removes it again on blur, and only assigns an
/// id/name when the field declares autofill hints. Since the element appears
/// only after the focus message reaches the engine, poll briefly for it.
void nameFocusedFormField(String id, String name) {
  unawaited(_stampWhenReady(id, name));
}

Future<void> _stampWhenReady(String id, String name) async {
  for (var attempt = 0; attempt < 25; attempt++) {
    final element = _editingElement();
    if (element != null) {
      element.setProperty('id'.toJS, id.toJS);
      element.setProperty('name'.toJS, name.toJS);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

/// The focused field's editing element, if the engine has created it yet.
/// Elements for autofill-enabled fields are never queried here (they carry
/// their own id/name and are kept dormant, offscreen, between uses); our
/// no-autofill fields are removed from the DOM on blur, so any live
/// `flt-text-editing` element belongs to the currently focused field.
JSObject? _editingElement() {
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final result = document.callMethod<JSAny?>(
    'querySelector'.toJS,
    '.flt-text-editing'.toJS,
  );
  if (result == null || result.isUndefinedOrNull) return null;
  return result as JSObject;
}
