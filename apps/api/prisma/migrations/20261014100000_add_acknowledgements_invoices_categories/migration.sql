-- CreateEnum
CREATE TYPE "PolicyAcknowledgementType" AS ENUM ('TERMS_CAPTAIN', 'TERMS_CLIENT', 'SENSITIVE_CATEGORY', 'PURCHASE_INVOICE');

-- CreateEnum
CREATE TYPE "PurchaseInvoiceStatus" AS ENUM ('SUBMITTED', 'CONFIRMED', 'DISPUTED');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "ShipmentCategory" ADD VALUE 'MEDICINES';
ALTER TYPE "ShipmentCategory" ADD VALUE 'PURCHASES';
ALTER TYPE "ShipmentCategory" ADD VALUE 'FOOD';
ALTER TYPE "ShipmentCategory" ADD VALUE 'ELECTRONICS';

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "estimatedBudget" DECIMAL(12,2);

-- AlterTable
ALTER TABLE "PricingSettings" ADD COLUMN     "disabledCategories" "ShipmentCategory"[] DEFAULT ARRAY[]::"ShipmentCategory"[];

-- CreateTable
CREATE TABLE "PolicyAcknowledgement" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "PolicyAcknowledgementType" NOT NULL,
    "policyVersion" TEXT NOT NULL,
    "orderId" TEXT,
    "category" "ShipmentCategory",
    "idempotencyKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ip" TEXT,

    CONSTRAINT "PolicyAcknowledgement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PurchaseInvoice" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "capturedById" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'EGP',
    "photoPath" TEXT NOT NULL,
    "note" TEXT,
    "status" "PurchaseInvoiceStatus" NOT NULL DEFAULT 'SUBMITTED',
    "clientRespondedAt" TIMESTAMP(3),
    "clientResponseReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PurchaseInvoice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PolicyAcknowledgement_idempotencyKey_key" ON "PolicyAcknowledgement"("idempotencyKey");

-- CreateIndex
CREATE INDEX "PolicyAcknowledgement_userId_type_createdAt_idx" ON "PolicyAcknowledgement"("userId", "type", "createdAt");

-- CreateIndex
CREATE INDEX "PolicyAcknowledgement_orderId_type_idx" ON "PolicyAcknowledgement"("orderId", "type");

-- CreateIndex
CREATE UNIQUE INDEX "PurchaseInvoice_orderId_key" ON "PurchaseInvoice"("orderId");

-- CreateIndex
CREATE INDEX "PurchaseInvoice_capturedById_createdAt_idx" ON "PurchaseInvoice"("capturedById", "createdAt");

-- AddForeignKey
ALTER TABLE "PolicyAcknowledgement" ADD CONSTRAINT "PolicyAcknowledgement_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PolicyAcknowledgement" ADD CONSTRAINT "PolicyAcknowledgement_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PurchaseInvoice" ADD CONSTRAINT "PurchaseInvoice_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PurchaseInvoice" ADD CONSTRAINT "PurchaseInvoice_capturedById_fkey" FOREIGN KEY ("capturedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
