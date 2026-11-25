-- Add vehicle make/model/color and profile photo to CaptainProfile (additive, nullable or defaulted).
ALTER TABLE "CaptainProfile" ADD COLUMN "vehicleMake" TEXT;
ALTER TABLE "CaptainProfile" ADD COLUMN "vehicleModel" TEXT;
ALTER TABLE "CaptainProfile" ADD COLUMN "vehicleColor" TEXT;
ALTER TABLE "CaptainProfile" ADD COLUMN "profilePhotoDocument" TEXT NOT NULL DEFAULT 'PENDING_UPLOAD';