// Type surface for the CommonJS token module (`tokens.js`). Keeps TSX call
// sites strongly typed while the runtime file stays plain-Node-requireable.

export type ColorToken =
  | 'primary'
  | 'primaryLight'
  | 'background'
  | 'surface'
  | 'surfaceDark'
  | 'textPrimary'
  | 'textSecondary'
  | 'textSecondaryMid'
  | 'textSecondaryStrong'
  | 'textBody'
  | 'textMuted'
  | 'textDisabled'
  | 'textOnDark'
  | 'border'
  | 'borderStrong'
  | 'borderSubtle'
  | 'chipBg'
  | 'danger'
  | 'dangerStrong'
  | 'dangerBg'
  | 'success'
  | 'warning'
  | 'warningBg'
  | 'warningBgSubtle'
  | 'warningText'
  | 'warningTextSoft';

export declare const colors: Record<ColorToken, string>;

export type RadiusToken = 'sm' | 'DEFAULT' | 'lg' | 'xl' | '2xl' | 'full';

export declare const radii: Record<RadiusToken, number>;
