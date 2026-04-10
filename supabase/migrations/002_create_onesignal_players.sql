-- Tabla para guardar los player IDs de OneSignal
CREATE TABLE IF NOT EXISTS user_onesignal_players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users NOT NULL,
  onesignal_player_id TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Función para actualizar updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger para actualizar updated_at
CREATE TRIGGER update_user_onesignal_players_updated_at
    BEFORE UPDATE ON user_onesignal_players
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Policy para que usuarios puedan ver/actualizar solo su propio registro
ALTER TABLE user_onesignal_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own player" ON user_onesignal_players
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own player" ON user_onesignal_players
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own player" ON user_onesignal_players
    FOR UPDATE USING (auth.uid() = user_id);
