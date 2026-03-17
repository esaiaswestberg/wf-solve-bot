import 'package:shared_preferences/shared_preferences.dart';

const selectedDictionaryPreferenceKey = 'selected_dictionary_path';

abstract class DictionarySelectionStore {
  Future<String?> loadSelectedDictionaryId();
  Future<void> saveSelectedDictionaryId(String id);
}

class SharedPreferencesDictionarySelectionStore
    implements DictionarySelectionStore {
  const SharedPreferencesDictionarySelectionStore();

  Future<SharedPreferences> get _preferences async {
    return SharedPreferences.getInstance();
  }

  @override
  Future<String?> loadSelectedDictionaryId() async {
    final preferences = await _preferences;
    return preferences.getString(selectedDictionaryPreferenceKey);
  }

  @override
  Future<void> saveSelectedDictionaryId(String id) async {
    final preferences = await _preferences;
    await preferences.setString(selectedDictionaryPreferenceKey, id);
  }
}
