export const EGYPT_GOVERNORATE_CODES = [
  '01', '02', '03', '04', '11', '12', '13', '14', '15', '16', '17', '18', '19',
  '21', '22', '23', '24', '25', '26', '27', '28', '29', '31', '32', '33', '34', '35', '88',
] as const;

export const EGYPT_GOVERNORATE_NAMES = [
  'Cairo',
  'Alexandria',
  'Port Said',
  'Suez',
  'Damietta',
  'Dakahlia',
  'Sharqia',
  'Qalyubia',
  'Kafr El Sheikh',
  'Gharbia',
  'Monufia',
  'Beheira',
  'Ismailia',
  'Giza',
  'Beni Suef',
  'Fayoum',
  'Minya',
  'Assiut',
  'Sohag',
  'Qena',
  'Aswan',
  'Luxor',
  'Red Sea',
  'New Valley',
  'Matrouh',
  'North Sinai',
  'South Sinai',
  'Egyptians born abroad',
] as const;

export type EgyptGovernorateName = (typeof EGYPT_GOVERNORATE_NAMES)[number];

export function isEgyptianGovernorateName(name: unknown): name is EgyptGovernorateName {
  return typeof name === 'string' && (EGYPT_GOVERNORATE_NAMES as readonly string[]).includes(name.trim());
}

export function governorateCodeToName(code: string): EgyptGovernorateName | null {
  const map: Record<string, EgyptGovernorateName> = {
    '01': 'Cairo',
    '02': 'Alexandria',
    '03': 'Port Said',
    '04': 'Suez',
    '11': 'Damietta',
    '12': 'Dakahlia',
    '13': 'Sharqia',
    '14': 'Qalyubia',
    '15': 'Kafr El Sheikh',
    '16': 'Gharbia',
    '17': 'Monufia',
    '18': 'Beheira',
    '19': 'Ismailia',
    '21': 'Giza',
    '22': 'Beni Suef',
    '23': 'Fayoum',
    '24': 'Minya',
    '25': 'Assiut',
    '26': 'Sohag',
    '27': 'Qena',
    '28': 'Aswan',
    '29': 'Luxor',
    '31': 'Red Sea',
    '32': 'New Valley',
    '33': 'Matrouh',
    '34': 'North Sinai',
    '35': 'South Sinai',
    '88': 'Egyptians born abroad',
  };
  return map[code] ?? null;
}

function isValidDate(y: number, m: number, d: number): boolean {
  const date = new Date(y, m - 1, d);
  return date.getFullYear() === y && date.getMonth() === m - 1 && date.getDate() === d;
}

export interface EgyptianNationalIdResult {
  valid: boolean;
  error?: string;
  birthYear?: number;
  birthMonth?: number;
  birthDay?: number;
  governorateCode?: string;
  age?: number;
}

export function validateEgyptianNationalId(id: string, referenceDate: Date = new Date()): EgyptianNationalIdResult {
  const normalized = (id ?? '').trim();
  if (!/^\d{14}$/.test(normalized)) {
    return { valid: false, error: 'National ID must be exactly 14 digits' };
  }

  const century = normalized[0];
  let fullYear: number;
  if (century === '2') {
    fullYear = 1900 + parseInt(normalized.slice(1, 3), 10);
  } else if (century === '3') {
    fullYear = 2000 + parseInt(normalized.slice(1, 3), 10);
  } else {
    return { valid: false, error: 'National ID must start with century digit 2 or 3' };
  }

  const month = parseInt(normalized.slice(3, 5), 10);
  const day = parseInt(normalized.slice(5, 7), 10);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return { valid: false, error: 'National ID contains an invalid birth date' };
  }
  if (!isValidDate(fullYear, month, day)) {
    return { valid: false, error: 'National ID contains an impossible birth date' };
  }

  const governorateCode = normalized.slice(7, 9);
  if (!(EGYPT_GOVERNORATE_CODES as readonly string[]).includes(governorateCode)) {
    return { valid: false, error: 'National ID contains an invalid governorate code' };
  }

  let age = referenceDate.getFullYear() - fullYear;
  const mDiff = referenceDate.getMonth() - (month - 1);
  const dDiff = referenceDate.getDate() - day;
  if (mDiff < 0 || (mDiff === 0 && dDiff < 0)) {
    age = age - 1;
  }
  if (age < 18) {
    return { valid: false, error: 'Captain must be at least 18 years old' };
  }

  return {
    valid: true,
    birthYear: fullYear,
    birthMonth: month,
    birthDay: day,
    governorateCode,
    age,
  };
}
