-- AlterTable
ALTER TABLE "CaptainProfile" ADD COLUMN     "isOnline" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "lastLat" DOUBLE PRECISION,
ADD COLUMN     "lastLng" DOUBLE PRECISION,
ADD COLUMN     "lastSeenAt" TIMESTAMP(3),
ADD COLUMN     "serviceRadiusKm" DOUBLE PRECISION NOT NULL DEFAULT 10;

-- AlterTable
ALTER TABLE "PricingSettings" ADD COLUMN     "maxRadiusKm" DECIMAL(6,2) NOT NULL DEFAULT 15,
ADD COLUMN     "minRadiusKm" DECIMAL(6,2) NOT NULL DEFAULT 2;

-- CreateTable
CREATE TABLE "OrderSkip" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "captainId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OrderSkip_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "OrderSkip_captainId_createdAt_idx" ON "OrderSkip"("captainId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "OrderSkip_orderId_captainId_key" ON "OrderSkip"("orderId", "captainId");

-- AddForeignKey
ALTER TABLE "OrderSkip" ADD CONSTRAINT "OrderSkip_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "OrderSkip" ADD CONSTRAINT "OrderSkip_captainId_fkey" FOREIGN KEY ("captainId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
