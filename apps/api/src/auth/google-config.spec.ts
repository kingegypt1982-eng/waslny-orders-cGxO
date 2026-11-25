import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

describe('GET /auth/google/config', () => {
  const controller = new AuthController({} as AuthService);
  const savedClientId = process.env.GOOGLE_CLIENT_ID;

  afterEach(() => {
    if (savedClientId === undefined) delete process.env.GOOGLE_CLIENT_ID;
    else process.env.GOOGLE_CLIENT_ID = savedClientId;
  });

  it('returns the same client ID the API verifies as the token audience', () => {
    process.env.GOOGLE_CLIENT_ID = 'test-web-client-id';

    expect(controller.googleConfig()).toEqual({ clientId: 'test-web-client-id' });
  });

  it('returns an empty string when Google is not configured', () => {
    delete process.env.GOOGLE_CLIENT_ID;

    expect(controller.googleConfig()).toEqual({ clientId: '' });
  });
});
