-- AlterTable
ALTER TABLE "CaptainProfile" ADD COLUMN     "dateOfBirth" TIMESTAMP(3),
ADD COLUMN     "governorate" TEXT,
ADD COLUMN     "licenseNumber" TEXT,
ADD COLUMN     "nationalIdEncrypted" TEXT,
ADD COLUMN     "nationalIdHash" TEXT,
ADD COLUMN     "nationalIdLast4" TEXT,
ADD COLUMN     "vehicleRegistrationNumber" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "CaptainProfile_nationalIdHash_key" ON "CaptainProfile"("nationalIdHash");

-- CreateIndex
CREATE UNIQUE INDEX "CaptainProfile_licenseNumber_key" ON "CaptainProfile"("licenseNumber");
