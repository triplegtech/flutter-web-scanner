import 'dart:html' as html;

bool isDeviceLanguagePortuguese() {
  return html.window.navigator.language == 'pt_BR';
}