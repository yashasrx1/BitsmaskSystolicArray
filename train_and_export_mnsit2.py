import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
import numpy as np

# Set deterministic seed for 100% reproducible weights
SEED = 42
torch.manual_seed(SEED)
np.random.seed(SEED)

class UltimateMNISTNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(784, 16, bias=True)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 10, bias=True)

    def forward(self, x):
        x = x.view(-1, 784)
        x = self.relu(self.fc1(x))
        return self.fc2(x)

print("=========================================================")
print("[1/6] Training 2-Layer PyTorch Model...")
print("=========================================================")

transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize((0.1307,), (0.3081,))
])

train_dataset = datasets.MNIST('./data', train=True, download=True, transform=transform)
train_loader  = torch.utils.data.DataLoader(train_dataset, batch_size=64, shuffle=True)

model = UltimateMNISTNet()
optimizer = optim.Adam(model.parameters(), lr=0.01)
criterion = nn.CrossEntropyLoss()

model.train()
for batch_idx, (data, target) in enumerate(train_loader):
    optimizer.zero_grad()
    output = model(data)
    loss = criterion(output, target)
    loss.backward()
    optimizer.step()
    if batch_idx >= 300: break

# -------------------------------------------------------------------
# 2. QUANTIZATION & 40% SPARSITY PRUNING
# -------------------------------------------------------------------
print("\n[2/6] Quantizing Layers & Pruning FC1...")

# FC1 Weights & Biases
w_fc1_fp32 = model.fc1.weight.detach().numpy() # (16, 784)
b_fc1_fp32 = model.fc1.bias.detach().numpy()   # (16,)

scale_w1 = 127.0 / float(np.max(np.abs(w_fc1_fp32)))
w_fc1_int8 = np.clip(np.round(w_fc1_fp32 * scale_w1), -128, 127).astype(np.int8)

# Prune FC1 (40% Sparsity)
threshold = float(np.percentile(np.abs(w_fc1_int8), 40))
w_fc1_int8[np.abs(w_fc1_int8) <= threshold] = 0

# FC2 Weights & Biases
w_fc2_fp32 = model.fc2.weight.detach().numpy() # (10, 16)
b_fc2_fp32 = model.fc2.bias.detach().numpy()   # (10,)
scale_w2 = 127.0 / float(np.max(np.abs(w_fc2_fp32)))
w_fc2_int8 = np.clip(np.round(w_fc2_fp32 * scale_w2), -128, 127).astype(np.int8)

# Scale Biases to INT32
b_fc1_int32 = np.round(b_fc1_fp32 * scale_w1 * 64.0).astype(np.int32)
b_fc2_int32 = np.round(b_fc2_fp32 * scale_w2).astype(np.int32)

# -------------------------------------------------------------------
# 3. EXPORT MEMORY HEX FILES
# -------------------------------------------------------------------
print("\n[3/6] Exporting Hardware Hex Files...")

# FC1 Weights & Bitmasks (3,136 lines)
with open("weights_fc1.hex", "w") as f:
    for tile in range(4):
        r_start = tile * 4
        for k in range(784):
            w4 = [w_fc1_int8[r_start + r, k] for r in range(4)]
            bitmask = sum([(1 if int(w) != 0 else 0) << idx for idx, w in enumerate(w4)])
            f.write(f"{bitmask:1X}{''.join([f'{int(w) & 0xFF:02X}' for w in w4])}\n")

# FC1 Biases (16 lines)
with open("bias_fc1.hex", "w") as f:
    for b in b_fc1_int32:
        f.write(f"{int(b) & 0xFFFFFFFF:08X}\n")

# FC2 Weights (160 lines: 10 neurons x 16 inputs)
with open("weights_fc2.hex", "w") as f:
    for r in range(10):
        for c in range(16):
            f.write(f"{int(w_fc2_int8[r, c]) & 0xFF:02X}\n")

# FC2 Biases (10 lines)
with open("bias_fc2.hex", "w") as f:
    for b in b_fc2_int32:
        f.write(f"{int(b) & 0xFFFFFFFF:08X}\n")

# Image Pixels (784 lines)
test_dataset = datasets.MNIST('./data', train=False, download=True, transform=transform)
test_image_tensor, target_digit = test_dataset[0]
img_int8 = np.clip(np.round(test_image_tensor.numpy().flatten() * 64), -128, 127).astype(np.int8)

with open("image.hex", "w") as f:
    for p in img_int8:
        f.write(f"{int(p) & 0xFF:02X}\n")

print("[SUCCESS] All memory hex files generated successfully.")

# -------------------------------------------------------------------
# 4. GOLDEN REFERENCE SCORE CALCULATION
# -------------------------------------------------------------------
print("\n=========================================================")
print("[4/6] GOLDEN HARDWARE REFERENCE CALCULATION")
print("=========================================================")

# FC1 Computation
fc1_raw = np.dot(w_fc1_int8.astype(np.int32), img_int8.astype(np.int32)) + b_fc1_int32
fc1_relu = np.maximum(0, fc1_raw)
fc1_act_int8 = np.clip(fc1_relu >> 7, 0, 127).astype(np.int8) # Shift right 7 bits for INT8

# FC2 Computation
fc2_logits = np.dot(w_fc2_int8.astype(np.int32), fc1_act_int8.astype(np.int32)) + b_fc2_int32
predicted_digit = int(np.argmax(fc2_logits))

print(f"Target Label Digit : {target_digit}")
print(f"Predicted Digit    : {predicted_digit}")
print("\nFC2 Class Logits (Digits 0-9):")
for d, logit in enumerate(fc2_logits):
    print(f"  Digit [{d}]: Logit = {logit:8d}")

print("=========================================================")