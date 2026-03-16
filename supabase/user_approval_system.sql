-- 1. Add is_approved column to profiles
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT FALSE;

-- 2. Update existing accounts to approved (optional)
UPDATE profiles SET is_approved = TRUE WHERE is_onboarded = TRUE;
