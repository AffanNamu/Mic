import { sha256Hex } from './crypto.ts';

export type Ownership = 'own' | 'authorized';

export const CONSENT_VERSION = 'v1';

/**
 * The exact wording a user agrees to. The server owns it: clients fetch and
 * display it, and the hash of what was shown is stored with the consent, so it
 * is always possible to say what a given user agreed to. Changing the wording
 * requires a new version.
 */
const STATEMENTS: Record<Ownership, string> = {
  own:
    'This is my own voice. I agree that DeenVoice may store this recording and send it to its ' +
    'music provider to create a reusable voice profile, which will be used only to generate songs ' +
    'for my account. I understand the provider may keep or use voice data under its own terms, ' +
    'that I can revoke this permission and delete the voice at any time, and that deleting it ' +
    'here may not immediately remove copies held by the provider.',
  authorized:
    'The person whose voice is in this recording has given me explicit permission to create and ' +
    'use a voice profile from it, and I can show that permission if asked. I agree that DeenVoice ' +
    'may store this recording and send it to its music provider to create a reusable voice ' +
    'profile, used only to generate songs for my account. I understand the provider may keep or ' +
    'use voice data under its own terms, that this permission can be revoked and the voice ' +
    'deleted at any time, and that deleting it here may not immediately remove copies held by ' +
    'the provider.',
};

export function consentStatement(version: string, ownership: Ownership): { text: string; sha256: string } | null {
  if (version !== CONSENT_VERSION) return null;
  const text = STATEMENTS[ownership];
  return { text, sha256: sha256Hex(text) };
}

export function allConsentStatements() {
  return {
    version: CONSENT_VERSION,
    statements: (Object.keys(STATEMENTS) as Ownership[]).map((ownership) => ({
      ownership,
      text: STATEMENTS[ownership],
    })),
  };
}
