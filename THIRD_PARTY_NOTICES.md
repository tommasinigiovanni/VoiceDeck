# Componenti di terze parti

- **FluidAudio 0.17.7**, Fluid Inference: Apache License 2.0. Sorgente: https://github.com/FluidInference/FluidAudio. Il pacchetto include FastCluster (BSD) e altri componenti; le rispettive licenze sono conservate nel sorgente della dipendenza risolta da SwiftPM.
- **NVIDIA Nemotron 3 Diarization**, conversione Core ML di Fluid Inference: OpenMDW License Agreement 1.1. I pesi sono scaricati separatamente al primo utilizzo da https://huggingface.co/FluidInference/nemotron-3-diarization-coreml. Modello originale: https://huggingface.co/nvidia/Nemotron-3-Diarization. I pesi non sono inclusi nell’app.
- **NVIDIA Nemotron 3.5 Transcribe** viene utilizzato come servizio tramite OpenRouter; i pesi di trascrizione non sono distribuiti con l’app.
- **NVIDIA Parakeet TDT 0.6B v3**, conversione Core ML di Fluid Inference: Creative Commons Attribution 4.0. Modello originale: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3. Conversione scaricata separatamente: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml. I pesi non sono inclusi nell’app. Licenza: https://creativecommons.org/licenses/by/4.0/.

I nomi NVIDIA, Nemotron e OpenRouter appartengono ai rispettivi titolari. Questa app non è un prodotto ufficiale NVIDIA o OpenRouter.
