-- Additive: store the admin's rejection reason so the captain can see it
ALTER TABLE "CaptainProfile" ADD COLUMN "rejectionReason" TEXT;
