import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseClientManager {
  static final SupabaseClientManager _instance = SupabaseClientManager._internal();
  late final SupabaseClient client;

  static const String supabaseUrl = 'https://khyvcztkvwmizgdcskdi.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtoeXZjenRrdndtaXpnZGNza2RpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE0MTY3NTYsImV4cCI6MjA2Njk5Mjc1Nn0.l-jchvf3H60vlLIAsmJz1j3xk7pGoonKL-10ruKOA84';

  factory SupabaseClientManager() {
    return _instance;
  }

  SupabaseClientManager._internal() {
    client = SupabaseClient(supabaseUrl, anonKey);
  }
}
