import os
from openai import OpenAI
from dotenv import load_dotenv
from gtts import gTTS

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

def chat_with_gpt(prompt):
    response = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[{"role": "user", "content": prompt}]
    )
    return response.choices[0].message.content

def speak(text):
    tts = gTTS(text)
    tts.save("response.mp3")
    os.system("afplay response.mp3")  # MacOS audio player

if __name__ == "__main__":
    print("ChatGPT Voice Assistant - type 'exit' to quit.")
    while True:
        user_input = input("You: ")
        if user_input.lower() == "exit":
            break
        answer = chat_with_gpt(user_input)
        print(f"ChatGPT: {answer}")
        speak(answer)
